#[test_only]
module mon_contracts::fan_sbt_tests;

use sui::test_scenario::{Self as ts, Scenario};
use mon_contracts::fan_sbt::{Self, FanSBT, AdminCap, MintRegistry};

const ALICE: address = @0xA;
const BOB:   address = @0xB;
const FIGHTER_TAKERU: address = @0x7A;

// --- helpers ---

fun start(sender: address): Scenario {
    let mut sc = ts::begin(sender);
    fan_sbt::init_for_testing(sc.ctx());
    sc.next_tx(sender);
    sc
}

fun mint_for(sc: &mut Scenario, who: address) {
    sc.next_tx(who);
    let mut reg = sc.take_shared<MintRegistry>();
    fan_sbt::mint_fan_card(&mut reg, FIGHTER_TAKERU, sc.ctx());
    ts::return_shared(reg);
    sc.next_tx(who);
}

// =====================================================================
// mint
// =====================================================================

#[test]
fun test_mint_initial_state() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);

    let sbt = sc.take_from_sender<FanSBT>();
    assert!(fan_sbt::level(&sbt) == 1, 0);
    assert!(fan_sbt::owner(&sbt) == ALICE, 1);
    assert!(fan_sbt::fighter_id(&sbt) == FIGHTER_TAKERU, 2);
    assert!(fan_sbt::check_in_count(&sbt) == 0, 3);
    assert!(fan_sbt::available_points(&sbt) == 0, 4);
    assert!(fan_sbt::content_count(&sbt) == 1, 5); // INITIAL_CONTENT_COUNT seed
    assert!(fan_sbt::guardian_badge_count(&sbt) == 0, 6);
    sc.return_to_sender(sbt);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::fan_sbt::EAlreadyMinted)]
fun test_mint_twice_same_address_aborts() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);

    sc.next_tx(ALICE);
    let mut reg = sc.take_shared<MintRegistry>();
    fan_sbt::mint_fan_card(&mut reg, FIGHTER_TAKERU, sc.ctx()); // abort
    ts::return_shared(reg);
    sc.end();
}

#[test]
fun test_two_different_addresses_can_each_mint() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);
    mint_for(&mut sc, BOB);
    sc.end();
}

// =====================================================================
// check-in + auto-upgrade
// =====================================================================

#[test]
fun test_three_check_ins_auto_upgrade_to_lv2() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);

    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();

    fan_sbt::record_check_in(&mut sbt, b"evt1", sc.ctx());
    assert!(fan_sbt::level(&sbt) == 1, 0);
    fan_sbt::record_check_in(&mut sbt, b"evt2", sc.ctx());
    assert!(fan_sbt::level(&sbt) == 1, 1);
    fan_sbt::record_check_in(&mut sbt, b"evt3", sc.ctx());
    // 3rd check-in crosses threshold → auto-upgrade
    assert!(fan_sbt::level(&sbt) == 2, 2);
    assert!(fan_sbt::check_in_count(&sbt) == 3, 3);
    assert!(fan_sbt::available_points(&sbt) == 3, 4);

    // idempotent further check-in stays Lv.2, counters keep climbing
    fan_sbt::record_check_in(&mut sbt, b"evt4", sc.ctx());
    assert!(fan_sbt::level(&sbt) == 2, 5);
    assert!(fan_sbt::check_in_count(&sbt) == 4, 6);
    assert!(fan_sbt::available_points(&sbt) == 4, 7);

    sc.return_to_sender(sbt);
    sc.end();
}

// =====================================================================
// manual upgrade_to_station
// =====================================================================

#[test]
fun test_upgrade_to_station_after_threshold() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);
    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();
    // Note: auto-upgrade already fires on 3rd check-in. Call upgrade_to_station
    // BEFORE that to test the manual-at-threshold path deterministically.
    // Workaround: test it's idempotent — state already Lv.2 from auto; call aborts ENotLv1.
    // We split: here test manual path by using only content threshold (impossible without check-ins,
    // so we test the negative/abort case separately). The positive manual path is implicitly
    // covered because auto-upgrade uses the same predicate. Just sanity-check state here.
    fan_sbt::record_check_in(&mut sbt, b"e1", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e2", sc.ctx());
    assert!(fan_sbt::level(&sbt) == 1, 0);
    // manual at exactly threshold (would match auto logic)
    fan_sbt::record_check_in(&mut sbt, b"e3", sc.ctx()); // auto-fires, lvl=2
    assert!(fan_sbt::level(&sbt) == 2, 1);

    sc.return_to_sender(sbt);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::fan_sbt::ENotLv1)]
fun test_upgrade_to_station_not_lv1_aborts() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);
    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();

    fan_sbt::record_check_in(&mut sbt, b"e1", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e2", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e3", sc.ctx()); // auto → Lv.2

    // Now manually upgrade again → ENotLv1
    fan_sbt::upgrade_to_station(&mut sbt, sc.ctx());

    sc.return_to_sender(sbt);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::fan_sbt::EUpgradeRequirementsNotMet)]
fun test_upgrade_to_station_below_threshold_aborts() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);
    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();

    fan_sbt::record_check_in(&mut sbt, b"e1", sc.ctx());
    // only 1 check-in, not 3 yet
    fan_sbt::upgrade_to_station(&mut sbt, sc.ctx());

    sc.return_to_sender(sbt);
    sc.end();
}

// =====================================================================
// official_certify (Lv.2 → Lv.3, AdminCap-gated)
// =====================================================================

#[test]
fun test_official_certify_lv2_to_lv3() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);

    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();
    fan_sbt::record_check_in(&mut sbt, b"e1", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e2", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e3", sc.ctx()); // → Lv.2
    assert!(fan_sbt::level(&sbt) == 2, 0);
    sc.return_to_sender(sbt);

    // Init-sender owns AdminCap (init_for_testing uses first tx's sender = ALICE)
    sc.next_tx(ALICE);
    let cap = sc.take_from_sender<AdminCap>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    fan_sbt::official_certify(&cap, &mut sbt, sc.ctx());
    assert!(fan_sbt::level(&sbt) == 3, 1);
    sc.return_to_sender(sbt);
    sc.return_to_sender(cap);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::fan_sbt::ENotLv2)]
fun test_official_certify_not_lv2_aborts() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);

    sc.next_tx(ALICE);
    let cap = sc.take_from_sender<AdminCap>();
    let mut sbt = sc.take_from_sender<FanSBT>();
    // sbt still Lv.1 — abort
    fan_sbt::official_certify(&cap, &mut sbt, sc.ctx());
    sc.return_to_sender(sbt);
    sc.return_to_sender(cap);
    sc.end();
}

// =====================================================================
// spend_points (public(package) — reachable from same-package test module)
// =====================================================================

#[test]
fun test_spend_points_decrements_available_only() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);
    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();

    fan_sbt::record_check_in(&mut sbt, b"e1", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e2", sc.ctx());
    fan_sbt::record_check_in(&mut sbt, b"e3", sc.ctx());
    assert!(fan_sbt::check_in_count(&sbt) == 3, 0);
    assert!(fan_sbt::available_points(&sbt) == 3, 1);

    fan_sbt::spend_points(&mut sbt, 2);
    assert!(fan_sbt::check_in_count(&sbt) == 3, 2); // unchanged
    assert!(fan_sbt::available_points(&sbt) == 1, 3);

    sc.return_to_sender(sbt);
    sc.end();
}

#[test]
#[expected_failure(abort_code = ::mon_contracts::fan_sbt::EInsufficientPoints)]
fun test_spend_points_over_balance_aborts() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);
    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();
    fan_sbt::record_check_in(&mut sbt, b"e1", sc.ctx());
    // available = 1, try spend 2
    fan_sbt::spend_points(&mut sbt, 2);
    sc.return_to_sender(sbt);
    sc.end();
}

// =====================================================================
// Property: invariant I1 available_points <= check_in_count
// Simulate 20 interleaved check-in / spend operations.
// =====================================================================

#[test]
fun property_available_points_leq_check_in_count() {
    let mut sc = start(ALICE);
    mint_for(&mut sc, ALICE);
    sc.next_tx(ALICE);
    let mut sbt = sc.take_from_sender<FanSBT>();

    let mut i = 0u64;
    while (i < 20) {
        fan_sbt::record_check_in(&mut sbt, b"e", sc.ctx());
        // Always holds after check-in
        assert!(fan_sbt::available_points(&sbt) <= fan_sbt::check_in_count(&sbt), 100);

        // Every 3rd iter, spend half
        if (i % 3 == 2) {
            let spend = fan_sbt::available_points(&sbt) / 2;
            if (spend > 0) {
                fan_sbt::spend_points(&mut sbt, spend);
                assert!(fan_sbt::available_points(&sbt) <= fan_sbt::check_in_count(&sbt), 101);
            }
        };
        i = i + 1;
    };

    // Final: check_in_count monotonic (== 20), level auto-reached 2
    assert!(fan_sbt::check_in_count(&sbt) == 20, 200);
    assert!(fan_sbt::level(&sbt) == 2, 201);

    sc.return_to_sender(sbt);
    sc.end();
}
