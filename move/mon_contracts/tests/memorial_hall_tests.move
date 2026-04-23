#[test_only]
module mon_contracts::memorial_hall_tests;

use std::string;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self as ts, Scenario};
use mon_contracts::fan_sbt::{Self, FanSBT, AdminCap, MintRegistry};
use mon_contracts::memorial_hall::{Self, MemorialMoment};

const ADMIN:   address = @0xAD;
const ALICE:   address = @0xA;
const BOB:     address = @0xB;
const CAROL:   address = @0xC;
const FIGHTER: address = @0x7A;

const STATUS_FINALIZED: u8 = 1;
const STATUS_EXPIRED:   u8 = 2;

// --- helpers ---

fun start(): Scenario {
    let mut sc = ts::begin(ADMIN);
    fan_sbt::init_for_testing(sc.ctx());
    sc.next_tx(ADMIN);
    sc
}

fun mint_for(sc: &mut Scenario, who: address) {
    sc.next_tx(who);
    let mut reg = sc.take_shared<MintRegistry>();
    fan_sbt::mint_fan_card(&mut reg, FIGHTER, sc.ctx());
    ts::return_shared(reg);
    sc.next_tx(who);
}

/// Mint + 3 check-ins → Lv.2, leaves SBT owned by `who` with 3 available points.
fun level_up_to_station(sc: &mut Scenario, who: address) {
    mint_for(sc, who);
    sc.next_tx(who);
    let mut sbt = sc.take_from_sender<FanSBT>();
    fan_sbt::record_check_in(&mut sbt, b"e1", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e2", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e3", sc.ctx());
    assert!(fan_sbt::level(&sbt) == 2, 0);
    sc.return_to_sender(sbt);
}

fun propose_by(sc: &mut Scenario, who: address, clock: &Clock) {
    sc.next_tx(who);
    let sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::propose_moment(
        &sbt,
        string::utf8(b"Takeru KO @ K-1 2026"),
        string::utf8(b"best moment"),
        string::utf8(b"walrus_blob_abc"),
        clock,
        sc.ctx(),
    );
    sc.return_to_sender(sbt);
    sc.next_tx(who);
}

// =====================================================================
// propose_moment
// =====================================================================

#[test]
fun test_propose_moment_by_lv2_station() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);

    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    let m = sc.take_shared<MemorialMoment>();
    assert!(memorial_hall::status(&m) == 0, 0); // CANDIDATE
    assert!(memorial_hall::total_points(&m) == 0, 1);
    assert!(memorial_hall::total_guardians(&m) == 0, 2);
    assert!(memorial_hall::proposer(&m) == ALICE, 3);
    assert!(memorial_hall::proposer_tier(&m) == 2, 4); // Lv.2 → tier 2
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::memorial_hall::EProposerNotStation)]
fun test_propose_by_lv1_aborts() {
    let mut sc = start();
    mint_for(&mut sc, ALICE); // still Lv.1

    let clock = clock::create_for_testing(sc.ctx());
    sc.next_tx(ALICE);
    let sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::propose_moment(
        &sbt,
        string::utf8(b"t"),
        string::utf8(b"d"),
        string::utf8(b"b"),
        &clock,
        sc.ctx(),
    );
    sc.return_to_sender(sbt);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
fun test_propose_by_lv3_sets_tier_1() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);

    // upgrade ALICE to Lv.3 via AdminCap (ADMIN owns it from init)
    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();
    fan_sbt::official_certify(&cap, &mut sbt, sc.ctx());
    assert!(fan_sbt::level(&sbt) == 3, 0);
    sc.return_to_sender(sbt);
    sc.next_tx(ADMIN);
    sc.return_to_sender(cap);

    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    let m = sc.take_shared<MemorialMoment>();
    assert!(memorial_hall::proposer_tier(&m) == 1, 1); // Lv.3 → tier 1
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

// =====================================================================
// vote_moment
// =====================================================================

#[test]
fun test_vote_first_time_creates_guardian_entry() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE); // proposer
    level_up_to_station(&mut sc, BOB);   // voter, 3 points available
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(BOB);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    let sbt_id = object::id(&sbt);
    memorial_hall::vote_moment(&mut m, &mut sbt, 2, &clock);

    assert!(memorial_hall::total_points(&m) == 2, 0);
    assert!(memorial_hall::total_guardians(&m) == 1, 1);
    assert!(memorial_hall::is_guardian(&m, sbt_id), 2);
    assert!(memorial_hall::guardian_rank(&m, sbt_id) == 1, 3);
    assert!(memorial_hall::guardian_tier(&m, sbt_id) == 1, 4); // rank 1 → gold
    assert!(memorial_hall::guardian_points(&m, sbt_id) == 2, 5);
    assert!(fan_sbt::available_points(&sbt) == 1, 6); // 3 - 2

    sc.return_to_sender(sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
fun test_vote_accumulates_without_changing_rank() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    level_up_to_station(&mut sc, BOB);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(BOB);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    let sbt_id = object::id(&sbt);
    memorial_hall::vote_moment(&mut m, &mut sbt, 1, &clock);
    memorial_hall::vote_moment(&mut m, &mut sbt, 2, &clock);

    assert!(memorial_hall::total_points(&m) == 3, 0);
    assert!(memorial_hall::total_guardians(&m) == 1, 1); // still 1 guardian
    assert!(memorial_hall::guardian_rank(&m, sbt_id) == 1, 2);
    assert!(memorial_hall::guardian_points(&m, sbt_id) == 3, 3);

    sc.return_to_sender(sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
fun test_multiple_voters_rank_by_arrival_order() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    level_up_to_station(&mut sc, BOB);
    level_up_to_station(&mut sc, CAROL);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    // BOB votes first → rank 1
    sc.next_tx(BOB);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut bob_sbt = sc.take_from_sender<FanSBT>();
    let bob_id = object::id(&bob_sbt);
    memorial_hall::vote_moment(&mut m, &mut bob_sbt, 1, &clock);
    sc.return_to_sender(bob_sbt);
    ts::return_shared(m);

    // CAROL votes second → rank 2
    sc.next_tx(CAROL);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut carol_sbt = sc.take_from_sender<FanSBT>();
    let carol_id = object::id(&carol_sbt);
    memorial_hall::vote_moment(&mut m, &mut carol_sbt, 1, &clock);

    assert!(memorial_hall::guardian_rank(&m, bob_id) == 1, 0);
    assert!(memorial_hall::guardian_rank(&m, carol_id) == 2, 1);
    assert!(memorial_hall::guardian_tier(&m, bob_id) == 1, 2);   // gold
    assert!(memorial_hall::guardian_tier(&m, carol_id) == 1, 3); // gold
    assert!(memorial_hall::total_guardians(&m) == 2, 4);

    sc.return_to_sender(carol_sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::memorial_hall::EVotePointsZero)]
fun test_vote_zero_points_aborts() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    level_up_to_station(&mut sc, BOB);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(BOB);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::vote_moment(&mut m, &mut sbt, 0, &clock);
    sc.return_to_sender(sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::memorial_hall::EMomentNotCandidate)]
fun test_vote_on_finalized_aborts() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    level_up_to_station(&mut sc, BOB);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut m = sc.take_shared<MemorialMoment>();
    memorial_hall::finalize_season(&cap, &mut m, STATUS_FINALIZED);
    ts::return_shared(m);
    sc.return_to_sender(cap);

    sc.next_tx(BOB);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::vote_moment(&mut m, &mut sbt, 1, &clock);
    sc.return_to_sender(sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

// =====================================================================
// finalize_season
// =====================================================================

#[test]
fun test_finalize_candidate_to_finalized() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut m = sc.take_shared<MemorialMoment>();
    memorial_hall::finalize_season(&cap, &mut m, STATUS_FINALIZED);
    assert!(memorial_hall::status(&m) == STATUS_FINALIZED, 0);
    ts::return_shared(m);
    sc.return_to_sender(cap);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
fun test_finalize_candidate_to_expired() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut m = sc.take_shared<MemorialMoment>();
    memorial_hall::finalize_season(&cap, &mut m, STATUS_EXPIRED);
    assert!(memorial_hall::status(&m) == STATUS_EXPIRED, 0);
    ts::return_shared(m);
    sc.return_to_sender(cap);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::memorial_hall::EInvalidStatusTransition)]
fun test_finalize_twice_aborts() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut m = sc.take_shared<MemorialMoment>();
    memorial_hall::finalize_season(&cap, &mut m, STATUS_FINALIZED);
    memorial_hall::finalize_season(&cap, &mut m, STATUS_FINALIZED); // abort
    ts::return_shared(m);
    sc.return_to_sender(cap);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::memorial_hall::EInvalidStatusTransition)]
fun test_finalize_with_invalid_status_aborts() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut m = sc.take_shared<MemorialMoment>();
    memorial_hall::finalize_season(&cap, &mut m, 99);
    ts::return_shared(m);
    sc.return_to_sender(cap);
    clock::destroy_for_testing(clock);
    sc.end();
}

// =====================================================================
// mint_guardian_badge
// =====================================================================

#[test]
fun test_mint_badge_after_finalize() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    level_up_to_station(&mut sc, BOB);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(BOB);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::vote_moment(&mut m, &mut sbt, 1, &clock);
    sc.return_to_sender(sbt);
    ts::return_shared(m);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut m = sc.take_shared<MemorialMoment>();
    memorial_hall::finalize_season(&cap, &mut m, STATUS_FINALIZED);
    ts::return_shared(m);
    sc.return_to_sender(cap);

    sc.next_tx(BOB);
    let m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    assert!(fan_sbt::guardian_badge_count(&sbt) == 0, 0);
    memorial_hall::mint_guardian_badge(&m, &mut sbt, &clock, sc.ctx());
    assert!(fan_sbt::guardian_badge_count(&sbt) == 1, 1);
    sc.return_to_sender(sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::memorial_hall::EMomentNotFinalized)]
fun test_mint_badge_before_finalize_aborts() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    level_up_to_station(&mut sc, BOB);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(BOB);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::vote_moment(&mut m, &mut sbt, 1, &clock);
    // still CANDIDATE
    memorial_hall::mint_guardian_badge(&m, &mut sbt, &clock, sc.ctx());
    sc.return_to_sender(sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::memorial_hall::ENotGuardian)]
fun test_mint_badge_non_voter_aborts() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    level_up_to_station(&mut sc, BOB);   // will NOT vote
    level_up_to_station(&mut sc, CAROL);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    // Only CAROL votes
    sc.next_tx(CAROL);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::vote_moment(&mut m, &mut sbt, 1, &clock);
    sc.return_to_sender(sbt);
    ts::return_shared(m);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut m = sc.take_shared<MemorialMoment>();
    memorial_hall::finalize_season(&cap, &mut m, STATUS_FINALIZED);
    ts::return_shared(m);
    sc.return_to_sender(cap);

    sc.next_tx(BOB);
    let m = sc.take_shared<MemorialMoment>();
    let mut bob_sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::mint_guardian_badge(&m, &mut bob_sbt, &clock, sc.ctx());
    sc.return_to_sender(bob_sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

#[test]
// Duplicate mint aborts inside sui::dynamic_field::add. Stdlib abort code
// not pinned to avoid coupling to internals — we only assert it fails.
#[expected_failure]
fun test_mint_badge_duplicate_aborts() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    level_up_to_station(&mut sc, BOB);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    sc.next_tx(BOB);
    let mut m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::vote_moment(&mut m, &mut sbt, 1, &clock);
    sc.return_to_sender(sbt);
    ts::return_shared(m);

    sc.next_tx(ADMIN);
    let cap = sc.take_from_sender<AdminCap>();
    let mut m = sc.take_shared<MemorialMoment>();
    memorial_hall::finalize_season(&cap, &mut m, STATUS_FINALIZED);
    ts::return_shared(m);
    sc.return_to_sender(cap);

    sc.next_tx(BOB);
    let m = sc.take_shared<MemorialMoment>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    memorial_hall::mint_guardian_badge(&m, &mut sbt, &clock, sc.ctx());
    memorial_hall::mint_guardian_badge(&m, &mut sbt, &clock, sc.ctx()); // abort
    sc.return_to_sender(sbt);
    ts::return_shared(m);
    clock::destroy_for_testing(clock);
    sc.end();
}

// =====================================================================
// rank → tier boundary coverage (31 voters)
// =====================================================================

#[test]
fun test_tier_boundaries_ranks_1_to_31() {
    let mut sc = start();
    level_up_to_station(&mut sc, ALICE);
    let clock = clock::create_for_testing(sc.ctx());
    propose_by(&mut sc, ALICE, &clock);

    let mut i = 0u64;
    while (i < 31) {
        let voter: address = sui::address::from_u256(((0x1000 + i) as u256));

        sc.next_tx(voter);
        let mut reg = sc.take_shared<MintRegistry>();
        fan_sbt::mint_fan_card(&mut reg, FIGHTER, sc.ctx());
        ts::return_shared(reg);

        sc.next_tx(voter);
        let mut sbt = sc.take_from_sender<FanSBT>();
        fan_sbt::record_check_in(&mut sbt, b"e", sc.ctx());
        fan_sbt::record_check_in(&mut sbt, b"e", sc.ctx());
        fan_sbt::record_check_in(&mut sbt, b"e", sc.ctx());
        let sbt_id = object::id(&sbt);

        let mut m = sc.take_shared<MemorialMoment>();
        memorial_hall::vote_moment(&mut m, &mut sbt, 1, &clock);

        let rank = memorial_hall::guardian_rank(&m, sbt_id);
        let tier = memorial_hall::guardian_tier(&m, sbt_id);
        assert!(rank == i + 1, 0);
        if (rank <= 3)       { assert!(tier == 1, 1) }  // gold
        else if (rank <= 10) { assert!(tier == 2, 2) }  // silver
        else if (rank <= 30) { assert!(tier == 3, 3) }  // bronze
        else                 { assert!(tier == 0, 4) }; // none

        ts::return_shared(m);
        sc.return_to_sender(sbt);
        i = i + 1;
    };

    clock::destroy_for_testing(clock);
    sc.end();
}
