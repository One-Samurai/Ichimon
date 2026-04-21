# MON Platform — Architecture Overview

## What is MON?

MON (門) is a Sui-based fan dojo platform for ONE Championship's ONE Samurai brand in Japan. Each fighter is a "gate" — fans enter as disciples with soulbound identity passes, earn honor through quests, and unlock exclusive content.

## Design Principles

1. **Soulbound identity over tradeable assets** — fans accumulate reputation, not speculation
2. **On-chain auto-rank** — instant feedback on quest completion
3. **Hybrid verification** — different quest types use different validators
4. **Tiered content gating** — simple tier assignment for content, complex rules under the hood
5. **Role-based shared objects** — multi-team operations without cap-passing complexity
6. **Compliance by design** — no gambling, no investment tokens, no high-value prizes

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Blockchain | Sui (Protocol 119, v1.69.1) |
| Smart Contracts | Move |
| Auth | zkLogin (Google, Apple, Twitch) |
| Storage | Walrus (encrypted media) |
| Access Control | Seal (tiered policy) |
| Frontend | Next.js + @mysten/dapp-kit |
| Data | gRPC + GraphQL + Custom Indexer |
| AI Agent | Off-chain LLM + on-chain Monban identity |
| Backend | Node.js (sponsor service, validator, AI orchestrator) |

## Object Model Summary

| Object | Type | Ownership |
|--------|------|-----------|
| RoleRegistry | Shared | Platform singleton |
| MonGate | Shared | Per fighter |
| MonPass | Owned | Per fan per gate (soulbound) |
| Quest | Shared | Per quest |
| Badge | Dynamic Field | Attached to MonPass |
| BadgeType | Shared | Per badge definition |
| Monban | Shared | Per gate AI agent |
| TierPolicy | Shared | Per gate content policy |

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Badge on MonPass | Dynamic Fields | Scalable, composable, no size bloat |
| Gate management | Shared + RBAC | Multi-team, multi-role operations |
| Quest verification | Hybrid | Different task types need different proofs |
| Badge transfer | Gate-scoped | "Same dojo" semantic, simple enforcement |
| XP ranking | Auto-rank on-chain | Instant feedback, Seal consistency |
| Content access | Tiered Seal policy | Admin-friendly, combinable conditions |
