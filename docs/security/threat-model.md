# MON Platform — Threat Model

**Date:** 2026-04-20
**Scope:** On-chain Move contracts + integration layer (zkLogin, Seal, Walrus)

---

## 1. Assets Under Protection

| Asset | Value | Location |
|-------|-------|----------|
| MonPass (fan identity) | Reputation, access rights | Sui (owned object) |
| Badge achievements | Social proof, content unlock | Sui (dynamic field) |
| XP/Rank state | Content tier access | Sui (MonPass field) |
| Gated content (videos) | Exclusive fan value | Walrus (encrypted) |
| RoleRegistry | Platform admin control | Sui (shared object) |
| Monban private key | AI agent authority | Off-chain secure storage |
| Fan PII | Privacy | Encrypted PostgreSQL |

---

## 2. Threat Actors

| Actor | Motivation | Capability |
|-------|-----------|------------|
| Malicious fan | Free XP/badges, content access | Craft transactions, replay proofs |
| Compromised validator | Issue fake completions | Sign arbitrary data |
| External attacker | Platform disruption | Network-level attacks |
| Insider (rogue admin) | Privilege abuse | Legitimate admin credentials |
| Competing platform | Discredit MON | Social engineering, exploits |

---

## 3. Attack Vectors & Mitigations

### 3.1 Signature Forgery

**Attack:** Craft fake validator signature to complete quests without doing them.

**Mitigation:**
- `ed25519_verify` in contract against known validator public key
- Validator address must exist in RoleRegistry with QUEST_VALIDATOR role
- Signature covers: `quest_id | pass_id | timestamp`
- Timestamp must be within ±5 min window (prevents pre-computation)

**Residual Risk:** Low — requires validator private key compromise.

### 3.2 Replay Attack

**Attack:** Submit same valid quest completion proof multiple times.

**Mitigation:**
- QuestCompletion stored as dynamic field on MonPass (key = quest_id)
- Non-repeatable quests: check existence before processing
- Repeatable quests: add timestamp to key for dedup within cooldown window

**Residual Risk:** Negligible.

### 3.3 Cross-Gate Manipulation

**Attack:** Use MonPass from Gate A to complete Quest in Gate B.

**Mitigation:**
- Every operation asserts `pass.gate_id == quest.gate_id`
- Badge transfer checks both passes share same gate_id

**Residual Risk:** Negligible — type system + runtime check.

### 3.4 Soulbound Bypass

**Attack:** Transfer MonPass to another address (sell accounts).

**Mitigation:**
- MonPass has only `key` ability (no `store`)
- Move type system prevents: public_transfer, public_share, wrapping
- Only `transfer::transfer` in mint function (module-scoped)

**Residual Risk:** User can share OAuth credentials (social layer — out of scope for on-chain enforcement).

### 3.5 Role Escalation

**Attack:** Non-admin calls grant_role to give themselves PlatformAdmin.

**Mitigation:**
- `grant_role` first line: assert caller has ROLE_PLATFORM_ADMIN
- No backdoor paths — all role-gated functions check RoleRegistry

**Residual Risk:** Low — requires admin key compromise.

### 3.6 Admin Lockout

**Attack:** Accidentally or maliciously revoke all PlatformAdmin roles.

**Mitigation:**
- `revoke_role` counts remaining admins before revoking
- Aborts with `ECannotRevokeLastAdmin` if count would reach 0

**Residual Risk:** Negligible.

### 3.7 Monban Key Compromise

**Attack:** Stolen AI agent private key used to issue unlimited rewards.

**Mitigation:**
- Rate limit: `action_count` per epoch on Monban object
- Full audit trail via `MonbanActionEvent`
- Immediate revocation via `revoke_role` (QUEST_VALIDATOR)
- Key rotation: register new Monban, revoke old

**Residual Risk:** Medium — window between compromise and detection. Mitigated by rate limit.

### 3.8 XP Integer Overflow

**Attack:** Accumulate XP to near u64::MAX, then overflow to 0.

**Mitigation:**
- Checked arithmetic in `add_xp`: abort if `pass.xp + amount > u64::MAX`

**Residual Risk:** Negligible.

### 3.9 Badge Supply Race Condition

**Attack:** Multiple concurrent mints exceed max_supply.

**Mitigation:**
- `BadgeType.minted_count` is a field on shared object (or owned by module)
- Sui consensus guarantees sequential access to shared objects
- Check `minted_count < max_supply` atomically with increment

**Residual Risk:** Negligible — consensus provides ordering guarantee.

### 3.10 Seal Policy Bypass (Content Leak)

**Attack:** Access Walrus content directly without going through Seal.

**Mitigation:**
- All content encrypted before upload to Walrus
- Decryption key only obtainable via Seal protocol
- Seal references on-chain MonPass state for access decision
- No plaintext content exists on Walrus

**Residual Risk:** Low — once decrypted client-side, user could screen-record (accepted trade-off, same as Netflix/YouTube).

### 3.11 Gas Sponsor Abuse

**Attack:** Bot farm creates thousands of MonPasses to drain sponsor wallet.

**Mitigation:**
- Rate limit per OAuth identity (1 join per gate per account)
- zkLogin binds to OAuth `sub` claim — creating new OAuth accounts has friction
- Monitor MonPass mint rate via indexer, alert on spikes > 10x baseline
- Backend can pause sponsorship if abuse detected

**Residual Risk:** Medium — determined attacker can create multiple OAuth accounts. Mitigated by monitoring + rate limits.

---

## 4. Trust Boundaries

```
┌──────────────────────────────────────────────┐
│ TRUST BOUNDARY: On-chain (immutable logic)   │
│                                              │
│  Move contracts enforce:                     │
│  - Role checks                              │
│  - Signature verification                   │
│  - Gate-scope enforcement                   │
│  - Soulbound constraints                    │
│  - Supply limits                            │
│  - XP overflow protection                   │
└──────────────────────────────────────────────┘
         │
         │ Trust assumptions:
         │ - Validator keys not compromised
         │ - Sui consensus is honest
         │
┌──────────────────────────────────────────────┐
│ TRUST BOUNDARY: Off-chain (operational)      │
│                                              │
│  Backend/Infra responsible for:              │
│  - zkLogin salt service availability         │
│  - Monban key security (HSM recommended)     │
│  - Gas sponsor budget management             │
│  - Content encryption before Walrus upload   │
│  - PII protection (APPI compliance)          │
│  - Monitoring and incident response          │
└──────────────────────────────────────────────┘
```

---

## 5. Recommendations

| Priority | Action | Owner |
|----------|--------|-------|
| P0 | Store Monban private key in HSM/KMS | Infrastructure |
| P0 | Implement rate limit monitoring + auto-pause | Backend |
| P1 | Security audit before mainnet (move-code-quality + sui-red-team) | Security |
| P1 | Multisig for UpgradeCap on mainnet | Ops |
| P2 | Incident runbook for key compromise scenarios | Ops |
| P2 | Regular role audit (who has what) | Admin |
