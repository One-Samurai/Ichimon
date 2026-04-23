/// FanSBT — soulbound fan card.
///
/// Soulbound guarantees:
///   - `has key` only (no `store`) → no `public_transfer` path.
///   - Module exposes no transfer-like entry; once `transfer::transfer` in `mint_fan_card`
///     lands, the owner is fixed for the object's lifetime.
///
/// State invariants (maintained by every mutating entry/public(package) fn):
///   I1. `available_points <= check_in_count` at all times.
///   I2. `check_in_count` is monotonically non-decreasing.
///   I3. `available_points` only decreases via `spend_points`, only increases via `record_check_in`.
///   I4. Field order is append-only — new fields must be added at the tail (Sui upgrade compat).
///
/// See docs/architecture/mvp-spec.md §3.
module mon_contracts::fan_sbt;

use sui::table::{Self, Table};
use sui::tx_context::sender;
use mon_contracts::events;

// === Errors ===
const EAlreadyMinted: u64 = 1;
const ENotLv1: u64 = 2;
const EUpgradeRequirementsNotMet: u64 = 3;
const ENotLv2: u64 = 4;
const EInsufficientPoints: u64 = 5;

// === Tunables ===
// Lv.1 → Lv.2 gate: demo must hit it within 30s (3 QR scans).
const LV2_CHECK_IN_THRESHOLD: u64 = 3;
const LV2_CONTENT_THRESHOLD: u64 = 1;
// Mock content seed injected at mint so demo can reach Lv.2 purely via check-ins.
const INITIAL_CONTENT_COUNT: u64 = 1;

// === Structs ===

// Field order is locked — append only. See invariant I4.
public struct FanSBT has key {
    id: UID,
    owner: address,
    level: u8,
    mint_time: u64,
    fighter_id: address,
    check_in_count: u64,
    available_points: u64,
    content_count: u64,
    contribution_count: u64,
    guardian_badge_count: u64,
}

public struct AdminCap has key, store { id: UID }

// Shared registry enforcing "one FanSBT per address".
// Owned objects cannot be globally queried cross-tx; a shared table is the
// only way to reject duplicate mints without trusting the caller.
public struct MintRegistry has key {
    id: UID,
    minted: Table<address, bool>,
}

// === Init ===

fun init(ctx: &mut TxContext) {
    transfer::transfer(AdminCap { id: object::new(ctx) }, sender(ctx));
    transfer::share_object(MintRegistry {
        id: object::new(ctx),
        minted: table::new<address, bool>(ctx),
    });
}

// === Entries ===

/// One card per address. Re-mint aborts with EAlreadyMinted.
public fun mint_fan_card(
    registry: &mut MintRegistry,
    fighter_id: address,
    ctx: &mut TxContext,
) {
    let who = sender(ctx);
    assert!(!registry.minted.contains(who), EAlreadyMinted);
    registry.minted.add(who, true);

    let now = ctx.epoch_timestamp_ms();
    let sbt = FanSBT {
        id: object::new(ctx),
        owner: who,
        level: 1,
        mint_time: now,
        fighter_id,
        check_in_count: 0,
        available_points: 0,
        content_count: INITIAL_CONTENT_COUNT,
        contribution_count: 0,
        guardian_badge_count: 0,
    };
    let sbt_id = object::id(&sbt);
    events::emit_fan_card_minted(sbt_id, who, fighter_id, now);
    // Soulbound: sole transfer call in this module; `key`-only prevents re-transfer.
    transfer::transfer(sbt, who);
}

/// Called directly by the card holder (owned object `&mut` authority cannot be delegated).
/// Backend only signs the QR payload off-chain; the tx itself is signed by the zkLogin session.
public fun record_check_in(
    sbt: &mut FanSBT,
    event_id: vector<u8>,
    ctx: &TxContext,
) {
    // I1 preserved: both sides of the inequality bump by 1.
    sbt.check_in_count = sbt.check_in_count + 1;
    sbt.available_points = sbt.available_points + 1;
    let now = ctx.epoch_timestamp_ms();
    events::emit_check_in_recorded(object::id(sbt), event_id, now);
    try_auto_upgrade(sbt, now);
}

/// Idempotent manual trigger — same gate as auto-upgrade, safe to call after meeting threshold.
public fun upgrade_to_station(sbt: &mut FanSBT, ctx: &TxContext) {
    assert!(sbt.level == 1, ENotLv1);
    assert!(
        sbt.check_in_count >= LV2_CHECK_IN_THRESHOLD
            && sbt.content_count >= LV2_CONTENT_THRESHOLD,
        EUpgradeRequirementsNotMet,
    );
    sbt.level = 2;
    events::emit_station_upgraded(object::id(sbt), 2, ctx.epoch_timestamp_ms());
}

/// Lv.2 → Lv.3, AdminCap-gated. Reuses StationUpgraded event (spec §5, new_level=3).
public fun official_certify(_: &AdminCap, sbt: &mut FanSBT, ctx: &TxContext) {
    assert!(sbt.level == 2, ENotLv2);
    sbt.level = 3;
    events::emit_station_upgraded(object::id(sbt), 3, ctx.epoch_timestamp_ms());
}

// === Internal ===

fun try_auto_upgrade(sbt: &mut FanSBT, now: u64) {
    if (sbt.level == 1
        && sbt.check_in_count >= LV2_CHECK_IN_THRESHOLD
        && sbt.content_count >= LV2_CONTENT_THRESHOLD) {
        sbt.level = 2;
        events::emit_station_upgraded(object::id(sbt), 2, now);
    }
}

// === public(package) — memorial_hall boundary ===

/// Voting burn. I1 preserved: only `available_points` decreases.
public(package) fun spend_points(sbt: &mut FanSBT, amount: u64) {
    assert!(sbt.available_points >= amount, EInsufficientPoints);
    sbt.available_points = sbt.available_points - amount;
}

public(package) fun inc_guardian_badge_count(sbt: &mut FanSBT) {
    sbt.guardian_badge_count = sbt.guardian_badge_count + 1;
}

/// UID handle so memorial_hall can attach GuardianBadge via dynamic_field.
/// Scoped to same package — external modules cannot tamper with dynamic fields.
public(package) fun uid_mut(sbt: &mut FanSBT): &mut UID { &mut sbt.id }

// === Read-only accessors ===

public fun level(sbt: &FanSBT): u8 { sbt.level }
public fun owner(sbt: &FanSBT): address { sbt.owner }
public fun fighter_id(sbt: &FanSBT): address { sbt.fighter_id }
public fun check_in_count(sbt: &FanSBT): u64 { sbt.check_in_count }
public fun available_points(sbt: &FanSBT): u64 { sbt.available_points }
public fun content_count(sbt: &FanSBT): u64 { sbt.content_count }
public fun contribution_count(sbt: &FanSBT): u64 { sbt.contribution_count }
public fun guardian_badge_count(sbt: &FanSBT): u64 { sbt.guardian_badge_count }

// === Test helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(ctx) }
