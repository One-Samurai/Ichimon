/// Event catalog. See docs/architecture/mvp-spec.md §5 — schema locked (frontend subscribes).
/// Fields are module-private; cross-module emitters must use the `emit_*` helpers.
module mon_contracts::events;

use sui::event;

public struct FanCardMinted       has copy, drop { sbt_id: ID, owner: address, fighter_id: address, timestamp: u64 }
public struct CheckInRecorded     has copy, drop { sbt_id: ID, event_id: vector<u8>, timestamp: u64 }
public struct StationUpgraded     has copy, drop { sbt_id: ID, new_level: u8, timestamp: u64 }
public struct ContributionLogged  has copy, drop { sbt_id: ID, target_sbt: ID, event_type: u8, timestamp: u64 }
public struct MomentProposed      has copy, drop { moment_id: ID, proposer: address, timestamp: u64 }
public struct VoteCast            has copy, drop { moment_id: ID, voter_sbt: ID, points: u64, is_new_guardian: bool, timestamp: u64 }
public struct GuardianBadgeMinted has copy, drop { sbt_id: ID, moment_id: ID, rank: u64, tier: u8, timestamp: u64 }

public(package) fun emit_fan_card_minted(sbt_id: ID, owner: address, fighter_id: address, timestamp: u64) {
    event::emit(FanCardMinted { sbt_id, owner, fighter_id, timestamp });
}

public(package) fun emit_check_in_recorded(sbt_id: ID, event_id: vector<u8>, timestamp: u64) {
    event::emit(CheckInRecorded { sbt_id, event_id, timestamp });
}

public(package) fun emit_station_upgraded(sbt_id: ID, new_level: u8, timestamp: u64) {
    event::emit(StationUpgraded { sbt_id, new_level, timestamp });
}

public(package) fun emit_contribution_logged(sbt_id: ID, target_sbt: ID, event_type: u8, timestamp: u64) {
    event::emit(ContributionLogged { sbt_id, target_sbt, event_type, timestamp });
}

public(package) fun emit_moment_proposed(moment_id: ID, proposer: address, timestamp: u64) {
    event::emit(MomentProposed { moment_id, proposer, timestamp });
}

public(package) fun emit_vote_cast(moment_id: ID, voter_sbt: ID, points: u64, is_new_guardian: bool, timestamp: u64) {
    event::emit(VoteCast { moment_id, voter_sbt, points, is_new_guardian, timestamp });
}

public(package) fun emit_guardian_badge_minted(sbt_id: ID, moment_id: ID, rank: u64, tier: u8, timestamp: u64) {
    event::emit(GuardianBadgeMinted { sbt_id, moment_id, rank, tier, timestamp });
}
