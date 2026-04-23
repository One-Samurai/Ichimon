# MON MVP System Spec（Backend / Contract）

> 對應 `docs/specs/Spec_v1.md`（Codex 削減後的精簡主線）
> 範圍：Sui Move 合約 + Node.js 中間層（mock seed + QR 簽章 + thin REST）
> 不含：前端 UI、Demo 腳本、Pitch（由 Kenny 負責）

---

## 1. 相對於舊 architecture 的差異（Scope Delta）

### 1.1 保留並改造

| 舊模組 | MVP 對應 | 改造重點 |
|--------|---------|---------|
| `mon_pass.move` | `fan_sbt.move` | soulbound 改用「key + no public transfer entry」；狀態欄位只留 `check_in_count` / `contribution_count` / `guardian_badge_count` 等 counter |
| `badge.move` | 併入 `memorial_hall.move`（GuardianBadge） | 不再是獨立 module，徽章直接在殿堂 finalize 時 mint，並以 dynamic field 掛 FanSBT 下 |
| `events.move` | 同名保留 | 擴充為主要「展示型資料管道」，前端用 events 查詢 |

### 1.2 新增

| 模組 | 功能 |
|------|------|
| `memorial_hall.move` | 提名候選時刻 / 投票（扣 check_in 點數）/ 發守護徽章 / 季結 |

### 1.3 刪除（勿復活）

`role_registry` / `mon_gate` / `quest` / `monban` / `seal_policy` — 原因見 Spec_v1.md「已砍掉的項目」。

### 1.4 後端中間層縮減

| 舊 | MVP |
|----|-----|
| Sponsor Service（Sponsored tx） | 預充 SUI 的單一 demo 帳號 + 前端 sign |
| Quest Validator（EC 簽章驗 quest） | 單一 Check-in QR 簽章（ed25519） |
| AI Orchestrator | ❌ |
| Custom Indexer + PostgreSQL | ❌ 改前端直查 events + mock JSON |
| Seal 解密閘道 | ❌ Walrus 只存靜態 blob id 做 showcase |

---

## 2. 合約模組清單

```
move/sources/
├── fan_sbt.move          # FanSBT soulbound 身份 + counters + AdminCap
├── memorial_hall.move    # MemorialMoment + GuardianEntry(Table) + mint GuardianBadge
└── events.move           # 所有 event struct 定義
```

**依賴圖**：

```
memorial_hall ──reads & mutates──▶ fan_sbt
memorial_hall ──emits──▶ events
fan_sbt       ──emits──▶ events
```

---

## 3. FanSBT Module 規格

### 3.1 Struct

```move
// INVARIANT: available_points <= check_in_count (at all times)
// check_in_count monotonically increases; available_points decreases only via _spend_points.
// 新欄位只 append 尾端（保留 Upgrade Compatible 語義）
public struct FanSBT has key {
    id: UID,
    owner: address,              // 僅顯示用，無 transfer entry
    level: u8,                   // 1=粉絲 / 2=認證站姐 / 3=官方公認
    mint_time: u64,
    fighter_id: address,         // demo 寫死武尊地址
    check_in_count: u64,         // 現場 check-in 次數（= 可用點數初始來源）
    available_points: u64,       // 可用於殿堂投票的點數（= check_in_count - 已花用）
    content_count: u64,          // mock 值，由 mint 時 seed
    contribution_count: u64,     // 被他人 check-in / 守護事件計數
    guardian_badge_count: u64,   // 當前持有徽章數
}

public struct AdminCap has key, store { id: UID }

// Shared object — enforces "one FanSBT per address" idempotency.
// owned object 無法跨 tx 查詢，必須用 shared Table 做 mint 籍貫。
public struct MintRegistry has key {
    id: UID,
    minted: Table<address, bool>,
}
```

**`init(ctx)`**：發 `AdminCap` 給 publisher + `share_object(MintRegistry)`。`content_count` 在 mint 時 seed 為 `1`（`INITIAL_CONTENT_COUNT`），讓 demo 純靠 3 次 check-in 即可觸發 Lv.2 自動升級。

**Soulbound 實作**：
- 有 `key` 無 `store` → 無法用 `public_transfer`
- module 不提供任何 `transfer`-類 entry function
- 升級 / counter 更新全走 `&mut FanSBT`

### 3.2 Entry Functions

| Function | 可見性 / 權限 | 作用 |
|----------|-----|------|
| `mint_fan_card(registry: &mut MintRegistry, fighter_id: address, ctx)` | `public`（任何人呼叫，registry 冪等守門） | 發 Lv.1 卡、綁 owner、emit `FanCardMinted`。同地址重呼 abort `EAlreadyMinted=1` |
| `record_check_in(sbt: &mut FanSBT, event_id: vector<u8>, ctx)` | `public`；**持卡人自呼**（owned `&mut` 不可轉授權） | `check_in_count += 1`、`available_points += 1`、emit `CheckInRecorded`、達門檻自動升 Lv.2 |
| `upgrade_to_station(sbt: &mut FanSBT, ctx)` | `public`；持卡人自呼 | 手動觸發 Lv.1→2（`record_check_in` 會自動觸發，此為 idempotent 補救入口） |
| `official_certify(cap: &AdminCap, sbt: &mut FanSBT, ctx)` | `public`；AdminCap gated | Lv.2→3，復用 `StationUpgraded { new_level: 3 }` event |
| `spend_points(sbt: &mut FanSBT, amount: u64)` | `public(package)` | 投票扣點，`available_points -= amount`（memorial_hall 呼叫） |
| `inc_guardian_badge_count(sbt: &mut FanSBT)` | `public(package)` | 發徽章時 +1 |
| `uid_mut(sbt: &mut FanSBT): &mut UID` | `public(package)` | 讓 memorial_hall 用 `dynamic_field::add` 掛 GuardianBadge |
| `level / owner / fighter_id / check_in_count / available_points / content_count / contribution_count / guardian_badge_count` | `public` 讀 accessor | 前端 / memorial_hall 讀狀態用 |

**錯誤碼**：`EAlreadyMinted=1`、`ENotLv1=2`、`EUpgradeRequirementsNotMet=3`、`ENotLv2=4`、`EInsufficientPoints=5`。

> **Tx 簽署責任**：QR 驗簽在後端（純 off-chain），但 `record_check_in` 的 tx **由前端以 zkLogin session 自行簽送**。後端**不代送**—owned object 的 `&mut` authority 不可轉授權。後端 `/api/checkin/qr/verify` 回傳的 `{ fighter_id, event_id }` 由前端打包成 PTB 送鏈。

### 3.3 升級門檻（MVP 寫死）

```
Lv.1 → Lv.2:  check_in_count >= 3  AND  content_count >= 1
Lv.2 → Lv.3:  AdminCap 手動
```

> 理由：demo 要能在 30 秒內從 Lv.1 升到 Lv.2（現場掃 3 次 QR）。

---

## 4. MemorialHall Module 規格

### 4.1 Struct

```move
public struct MemorialMoment has key, store {
    id: UID,
    title: String,
    description: String,
    media_walrus_blob_id: String,
    proposer: address,
    proposer_tier: u8,             // 1=官方 / 2=Lv.3站姐 / 3=聯名（MVP 只用 1/2）
    total_points: u64,
    total_guardians: u64,
    preservation_until: u64,       // mint 時 + 季長度
    status: u8,                    // 0=候選 / 1=已入選 / 2=已過期
    guardians: Table<ID, GuardianEntry>,  // key = FanSBT ID
}

public struct GuardianEntry has store {
    sbt_id: ID,
    points_contributed: u64,
    rank: u64,        // 投票當下給定序號
    tier: u8,         // 1=金(rank<=3) / 2=銀(<=10) / 3=銅(<=30)
    joined_at: u64,
}

public struct GuardianBadge has key, store {  // 掛 dynamic field 到 FanSBT
    id: UID,
    moment_id: ID,
    rank: u64,
    tier: u8,
    minted_at: u64,
}
```

### 4.2 Entry Functions

| Function | 檢查 | 作用 |
|----------|-----|------|
| `propose_moment(proposer_sbt: &FanSBT, title, desc, blob_id, ctx)` | `proposer_sbt.level >= 2` | 建立 MemorialMoment（shared object），emit `MomentProposed` |
| `vote_moment(moment: &mut, voter_sbt: &mut FanSBT, points: u64, ctx)` | `voter_sbt.available_points >= points` | `fan_sbt::_spend_points`；若首次投票→`Table::add` 新 `GuardianEntry`，否則累加；更新 `total_points` / `total_guardians` / rank / tier；emit `VoteCast` |
| `mint_guardian_badge(moment: &MemorialMoment, sbt: &mut FanSBT, ctx)` | `moment.status == 1`（已入選）且 sbt 有 `GuardianEntry` 且尚未領取 | mint `GuardianBadge`，用 `dynamic_field::add(&mut sbt.id, moment_id, badge)`，`fan_sbt::_inc_guardian_badge_count`，emit `GuardianBadgeMinted` |
| `finalize_season(&AdminCap, moment: &mut, ctx)` | AdminCap | 將 moment.status 從 0→1 或 0→2 |

**Table 使用注意（Codex 硬傷點）**：
- 前端**不**迭代 Table，只讀 `total_guardians` / `total_points` + events
- Rank 計算：投票當下用 `total_guardians + 1` 直接寫入 `GuardianEntry.rank`（不重排，demo 階段簡化）
- Tier 依 rank 計算：≤3 金、≤10 銀、≤30 銅、>30 無徽章

---

## 5. Events Module 規格

```move
public struct FanCardMinted      has copy, drop { sbt_id: ID, owner: address, fighter_id: address, timestamp: u64 }
public struct CheckInRecorded    has copy, drop { sbt_id: ID, event_id: vector<u8>, timestamp: u64 }
public struct StationUpgraded    has copy, drop { sbt_id: ID, new_level: u8, timestamp: u64 }
public struct ContributionLogged has copy, drop { sbt_id: ID, target_sbt: ID, event_type: u8, timestamp: u64 }
public struct MomentProposed     has copy, drop { moment_id: ID, proposer: address, timestamp: u64 }
public struct VoteCast           has copy, drop { moment_id: ID, voter_sbt: ID, points: u64, is_new_guardian: bool, timestamp: u64 }
public struct GuardianBadgeMinted has copy, drop { sbt_id: ID, moment_id: ID, rank: u64, tier: u8, timestamp: u64 }
```

所有 event 都用 `sui::event::emit`。前端/後端都用 event subscription（`suix_subscribeEvent`）或 pull（`queryEvents`）。

---

## 6. Backend 中間層規格（Node.js，最小化）

### 6.1 職責（唯一三件事）

1. **Mock Seed API**：回傳 10 位假站姐、5 支影片、3 個殿堂候選時刻
2. **Check-in QR 簽發 + 驗證**：ed25519 簽章，payload = `{ fighter_id, event_id, issued_at, nonce }`
3. ~~Thin Tx Relay~~（**砍掉**）：`FanSBT` 是 owned object，`&mut` authority 不可轉授權給後端。所有 tx 一律由前端 zkLogin session 自簽自送。

### 6.2 REST API

```
GET  /api/stations                     → 10 位假站姐 JSON（含 YT/IG 連結）
GET  /api/moments                      → 3 個殿堂候選時刻 JSON
GET  /api/fighter/takeru               → 武尊 profile + 賽事 JSON
POST /api/checkin/qr/issue             → 產生 QR payload（admin only，demo 用）
     body: { event_id }                  res: { qr_payload_base64, expires_at }
POST /api/checkin/qr/verify            → 驗簽 + 回 tx-ready payload
     body: { qr_payload_base64 }         res: { fighter_id, event_id, valid: true }
```

**不做**：資料庫、indexer、sponsor、AI、Walrus 上傳。

### 6.3 QR 簽章格式

```
payload = base64(json({
  fighter_id: "0x...",
  event_id: "2026_tokyo_checkin_01",
  issued_at: 1714320000,
  nonce: "uuid",
  sig: ed25519(sk_backend, sha256(fighter_id || event_id || issued_at || nonce))
}))
```

有效期：5 分鐘（`expires_at = issued_at + 300`）。

### 6.4 Mock Data 目錄結構

```
backend/mocks/
├── fighter_takeru.json    # 武尊個資 + 3 場真實賽事（照片、日期、對手）
├── stations.json          # 10 位假站姐（名字、頭像、YT/IG URL、追蹤數）
├── moments.json           # 3 個殿堂候選（title/desc/blob_id/proposer_tier）
└── events.json            # 武尊 YT 影片清單（標題 + URL + 縮圖）
```

---

## 7. 部署 / 環境

| 項 | 值 |
|----|---|
| 網路 | Sui Testnet |
| Gas | 預充單一 demo 帳號（~1 SUI 即足） |
| Admin key | 後端保管的 ed25519 keypair（AdminCap + QR 簽章合用或分兩把，建議分兩把） |
| Walrus | 手動上傳 1~2 個樣本 blob，blob id 寫死在 `moments.json` |
| zkLogin | Google 單一 provider；備案 = Sui wallet extension |

---

## 8. 介面契約（前後端鎖定用，Day 1 必須對齊）

### 8.1 合約 Function Signatures（Kenny 前端呼叫用）

```ts
// 部署後由後端提供 { PKG, MINT_REGISTRY_ID, ADMIN_CAP_ID } 給前端。

txb.moveCall({
  target: `${PKG}::fan_sbt::mint_fan_card`,
  arguments: [
    txb.object(MINT_REGISTRY_ID),   // shared object — 冪等守門
    txb.pure.address(FIGHTER_TAKERU),
  ],
});

txb.moveCall({
  target: `${PKG}::fan_sbt::record_check_in`,
  arguments: [txb.object(sbtId), txb.pure.vector("u8", eventIdBytes)],
});

txb.moveCall({
  target: `${PKG}::memorial_hall::vote_moment`,
  arguments: [txb.object(momentId), txb.object(sbtId), txb.pure.u64(points)],
});
```

**需要交付給前端的常數**：`PKG`（package id）、`MINT_REGISTRY_ID`（shared）、`ADMIN_CAP_ID`（僅 demo 帳號持有）。部署後寫進環境變數。

### 8.2 Event Schema（前端 subscription 讀）

見 §5，所有欄位名鎖定，改動需雙方同意。

### 8.3 Mock JSON Schema

見 §6.4，Kenny 先畫 UI，後端照 UI 需求反向微調欄位。

---

## 9. 開發階段切分（72h 內執行順序）

1. **Hour 0–4**：合約骨架 + `fan_sbt.move`（mint / check_in / upgrade）+ 單元測試
2. **Hour 4–10**：`memorial_hall.move`（propose / vote / mint_badge）+ Table 測試
3. **Hour 10–14**：events.move 完整化，部署到 testnet，給 Kenny package_id
4. **Hour 14–20**：Backend REST + Mock JSON + QR 簽章
5. **Hour 20–28**：zkLogin 整合協助（與 Kenny pair）
6. **Hour 28–36**：整合測試，調門檻數字
7. **Hour 36–48**：bug fix + demo 彩排 + 備案錄影

### 風險 checkpoint

| 時點 | 檢核 | 若失敗 |
|------|------|-------|
| H+12 | 合約部署 testnet 成功、events 可訂閱 | 延到 H+18 就切「本地 sui network + 錄影備案」 |
| H+24 | zkLogin 能登入並送 tx | 切一般 wallet |
| H+48 | 端到端 demo 閉環可重播 3 次 | 只保留 demo 主線，其他 hide |

---

## 10. 測試要求

- Move unit test：`fan_sbt` 升級門檻、`memorial_hall` 投票扣點 / Table add / rank tier 計算
- Monkey test（對齊專案 `test.md`）：
  - `record_check_in` 連呼 100 次（counter 不溢位）
  - `vote_moment` 投 0 點、投超過 available_points、同一 moment 多次投票（Table 累加而非重建）
  - 未入選的 moment 嘗試 `mint_guardian_badge`（應 abort）
  - 重複 `mint_guardian_badge`（dynamic field 已存在應 abort）
  - **不變量**：任意操作序列後 `available_points <= check_in_count` 恆成立（property test）
- Testnet 煙霧測試：部署後跑一次完整 flow（mint → 3 次 check-in → 升 Lv.2 → propose → vote → finalize → mint badge）

---

## 11. 對照表：Spec_v1.md 章節 → 本文件

| Spec_v1 章節 | 本文件章節 |
|-------------|-----------|
| 架構分層（精簡版） | §1, §2 |
| 資料 Schema | §3.1, §4.1 |
| 合約介面清單 | §3.2, §4.2 |
| 介面契約先對齊 | §8 |
| 風險清單 | §9 checkpoint |
| 已砍掉的項目 | §1.3 |
