# ONE × 門（MON）Build Spec

**專案**：Sui Hackathon × ONE Championship — 粉絲經濟平台
**Deadline**：2026-04-25 (六) 12:00 JST
**Demo**：4/28 CoinPost Tokyo in-person
**聚焦**：武尊（Takeru）單一拳手

> ⚠️ 本 spec 經過 Codex 技術審查（跑 2 次）削減，主線已收縮到可驗證鏈上閉環。
> 砍掉的項目在本文最後列出，勿復活。

---

## 一句話定位

> 把 K-pop 站哥站姐文化搬上 Sui，幫 ONE 在日本市場用粉絲經濟逆向紮根。

---

## 核心敘事（5 句話）

1. 日本市場不缺格鬥賽事，缺的是粉絲跟拳手的長期關係
2. K-pop / 啦啦隊已經驗證粉絲經濟能靠鐵粉社群撐起商業
3. 我們用 Sui 把這套模型上鏈 → 身份 + 貢獻 + 永久記憶
4. **粉絲的應援資產不屬於 ONE，屬於粉絲自己** → 解「ONE 會跑」的疑慮
5. ONE 走了，記憶還在鏈上，粉絲繼續自組織

---

## 架構分層（精簡版）

```
┌───────────────────────────────────────────────────┐
│  前端 (Next.js / React)                            │
│    • 武尊「門」頁面                                 │
│    • 站姐排行榜 + 社群 Profile 跳轉                  │
│    • 個人 SBT 名片 + 貢獻足跡                       │
│    • 記憶殿堂（候選時刻 / 投票 / 守護者徽章）         │
│    • 現場 check-in 掃碼模擬                         │
└───────────────────────────────────────────────────┘
                      ↕
┌───────────────────────────────────────────────────┐
│  Backend 中間層 (Node.js，最小化)                  │
│    • Mock 資料 seed（10 位假站姐、5 支影片、3 殿堂） │
│    • check-in QR 簽章驗證                          │
│    • 簡單 REST API（前端 ↔ 合約）                    │
└───────────────────────────────────────────────────┘
                      ↕
┌───────────────────────────────────────────────────┐
│  Sui Move 合約 + zkLogin                           │
│    • FanSBT 合約（身份卡 + 貢獻 counter）            │
│    • MemorialHall 合約（提名 / 投票 / 守護徽章）     │
│    • zkLogin（Google 登入）                         │
│    • Walrus：降級為 showcase（用靜態 blob id 展示）   │
└───────────────────────────────────────────────────┘
```

**刪除項**（Codex 建議）：
- ❌ YouTube / IG OAuth（整組砍）
- ❌ 自動抓取上鏈（改 mock）
- ❌ Sponsored Transaction（用預充 SUI 帳號）
- ❌ 法幣 → WAL 轉換（殿堂改用內建點數，不經 WAL）
- ❌ Content 合約（改用 mock 資料 + event emit）

---

## 分工 Checklist

### Kenny（前端 + 設計 + Demo）
- [ ] Next.js 專案骨架
- [ ] 武尊「門」頁面 UI
- [ ] 站姐排行榜 UI（10 位假資料，含 YT/IG 外連）
- [ ] SBT 名片頁 UI（等級、貢獻足跡、徽章陳列）
- [ ] 記憶殿堂頁面 UI（3 個候選 + 守護者清單 + 金銀銅徽章）
- [ ] 現場 check-in 掃 QR 模擬 UI（含升級動畫）
- [ ] Mock 資料設計（武尊真實照片、真實賽事、假站姐人設）
- [ ] Demo 5 分鐘腳本 + 預錄備份
- [ ] Pitch 投影片

### 夥伴（合約 + Sui 整合）
- [ ] Sui Move 合約：FanSBT + MemorialHall
- [ ] zkLogin 整合（Google 登入 → 錢包地址）
- [ ] 合約部署到 Sui Testnet
- [ ] 前端呼叫合約的 helper function（tx builder）
- [ ] Check-in QR 驗證邏輯（簡易簽章即可）
- [ ] Walrus showcase：上傳 1-2 個樣本 blob，讓 UI 能秀 blob id

### 共同
- [ ] 介面契約鎖定（合約 function signatures + event schema）
- [ ] Mock 資料 JSON 格式協商
- [ ] 每日 15 分鐘同步

---

## 資料 Schema（Sui Move 慣用法）

### FanSBT（粉絲 / 站姐身份卡）

**Soulbound 實現方式**：保留 `key` ability，**不提供 public transfer entry function**，module 內控生命週期。（不使用 `freeze_object`，因為卡片需要累積 check-in 狀態）

```move
struct FanSBT has key {
    id: UID,
    owner: address,              // 用於前端顯示，實際 transfer 被禁
    level: u8,                   // 1=粉絲 / 2=認證站姐 / 3=官方公認
    mint_time: u64,
    fighter_id: address,         // 綁定拳手（demo 只有武尊）
    check_in_count: u64,
    content_count: u64,          // 從 mock 讀取，不由鏈上累積
    contribution_count: u64,     // 被 check-in 貢獻 / 守護事件總計
    guardian_badge_count: u64,   // 持有徽章數（實際徽章用 dynamic field 掛）
}
```

**注意**：
- 不再有 `social_handles`（砍 OAuth）
- `guardian_badges` 不再是 vector，改用 dynamic field 掛在 SBT 下
- 不再有 `likes_received`（砍內容按讚）

### MemorialMoment（殿堂候選時刻）

**GuardianEntry 改用 Sui Table，不塞 vector**（Codex 硬傷糾正）：

```move
struct MemorialMoment has key {
    id: UID,
    title: String,
    description: String,
    media_walrus_blob_id: String,  // 靜態 blob id 即可（showcase）
    proposer: address,
    proposer_tier: u8,              // 1=官方 / 2=Lv.3站姐 / 3=聯名
    total_points: u64,
    total_guardians: u64,
    preservation_until: u64,
    status: u8,                     // 0=候選 / 1=已入選 / 2=已過期
    guardians: Table<ID, GuardianEntry>,  // ← 從 vector 改 Table
}

struct GuardianEntry has store {
    sbt_id: ID,
    points_contributed: u64,
    rank: u64,       // 第幾位守護者
    tier: u8,        // 1=金 / 2=銀 / 3=銅
    joined_at: u64,
}
```

### 事件（全部改用 event emit，不再存 persistent struct）

```move
// 原 ContentRecord / ContributionEvent 全改為 event
event::emit(FanCardMinted      { sbt_id, owner, fighter_id, timestamp })
event::emit(CheckInRecorded    { sbt_id, event_id, timestamp })
event::emit(ContributionLogged { sbt_id, target_sbt, event_type, timestamp })
event::emit(MomentProposed     { moment_id, proposer, timestamp })
event::emit(VoteCast           { moment_id, voter_sbt, points })
event::emit(GuardianBadgeMinted { sbt_id, moment_id, rank, tier })
event::emit(StationUpgraded    { sbt_id, new_level })
```

**設計原則**：
- 狀態型聚合（如 `check_in_count`）→ 存 SBT 上的 counter
- 展示 / 分析 / 歷史型資料 → emit event，前端用 indexer 讀

---

## 合約介面清單

### FanSBT Module

```move
// 不提供 public transfer entry → soulbound
public entry fun mint_fan_card(fighter_id: address, ctx: &mut TxContext)

public entry fun upgrade_to_station(sbt: &mut FanSBT, ctx: &mut TxContext)
  // Lv.1 → Lv.2，檢查 check_in_count 和 content_count 門檻

public entry fun official_certify(admin_cap: &AdminCap, sbt: &mut FanSBT)
  // Lv.2 → Lv.3（demo 不展示完整流程，保留函數能被 call）

public entry fun record_check_in(sbt: &mut FanSBT, event_id: vector<u8>, ctx: &mut TxContext)
  // 到場掃碼 → check_in_count += 1 + emit CheckInRecorded + 觸發升級檢查

public fun get_sbt_profile(sbt: &FanSBT): SBTProfile  // view only
```

**砍掉**：
- ❌ `bind_social`（不綁社群）
- ❌ `record_purchase_contribution`（併進 check-in）

### MemorialHall Module

```move
public entry fun propose_moment(
    proposer_sbt: &FanSBT,
    title: String,
    desc: String,
    walrus_blob_id: String,
    ctx: &mut TxContext
)

public entry fun vote_moment(
    moment: &mut MemorialMoment,
    voter_sbt: &mut FanSBT,
    points: u64,
    ctx: &mut TxContext
)
  // 用 voter_sbt 身上的「可用點數」計算（點數來自 check_in_count），不接 WAL

public entry fun mint_guardian_badge(
    moment: &MemorialMoment,
    sbt: &mut FanSBT,
    ctx: &mut TxContext
)
  // 達到守護門檻後發徽章

public entry fun finalize_season(admin: &AdminCap, season_id: u64)
```

**砍掉**：
- ❌ `extend_preservation` 吃 WAL → 改用內建點數投票，簡化

---

## Demo 5 分鐘腳本（Codex 建議版）

| 時間 | 畫面 | 旁白重點 |
|------|------|---------|
| 00:00-00:45 | Google 登入（zkLogin）→ 領武尊粉絲卡 | 零門檻、看不到 crypto |
| 00:45-01:30 | 進武尊「門」→ 站姐排行榜 → 點站姐跳 YouTube | ONE 官方的「尋找站姐」入口 |
| 01:30-02:30 | 模擬 4/29 現場 check-in（掃 QR）→ SBT 升級動畫 + 貢獻 +1 | 到場即貢獻，鏈上不可偽造 |
| 02:30-03:30 | 看自己 SBT 名片（Lv.2 進度條、貢獻足跡、持有徽章） | 時間 + 貢獻 = 身份資產 |
| 03:30-04:30 | 記憶殿堂：投票候選時刻 → 拿金徽章 | ONE 走了記憶還在、粉絲自組織 |
| 04:30-05:00 | Sui 技術覆蓋圖（zkLogin + Move + Walrus showcase）+ Impact 三句話 | 收尾 |

### 被砍掉的舊幕（Codex 指出是最弱 2 幕）
- ❌ ~~綁 YouTube 自動抓 5 支影片~~（最弱一幕，觀感像資料匯入）
- ❌ ~~結帳掃碼 + 模擬分潤~~（沒真支付會被當假流程）

這兩幕的敘事價值已併入「現場 check-in」和「SBT 名片」。

---

## 介面契約先對齊（動手前必做）

1. **FanSBT 的 soulbound 實現**：`key` ability + 不給 public transfer → Kenny 前端呼叫時不嘗試 transfer
2. **升級門檻數字**：Lv.1 → Lv.2 要 `check_in_count >= ?` 和 `content_count >= ?`，先 mock 設低值讓 demo 能一次升級
3. **Check-in QR 格式**：payload 結構（fighter_id + event_id + 簽章），backend 驗證、合約信任
4. **殿堂點數來源**：建議用 `check_in_count` 直接當可用點數，每次投票扣除
5. **Mock 資料 JSON**：武尊 3 個殿堂時刻 + 10 位站姐 + 每位站姐 5 支影片連結 + 徽章圖檔

---

## 風險清單（更新）

| 風險 | 緩解 |
|------|------|
| zkLogin 整合卡住（Codex 預測第一卡點） | 備案：一般 Sui wallet 登入；時間上限 12h，超過就切備案 |
| Walrus 上傳失敗 | 已降級為 showcase，用靜態 blob id + IPFS hash placeholder |
| Sui Testnet 不穩 | 錄預備 demo 影片，現場播放備案 |
| 時間不夠（Codex 估 66-98h，實際只有 72h） | 殿堂可用半靜態（投票 UI + 一筆真 tx），其他讀 mock |
| GuardianEntry Table 查詢複雜 | 前端讀 `total_guardians` 和 events 即可，不直接迭代 Table |

---

## 評審分數目標（Codex 估 vs 目標）

| 項目 | Codex 估（舊腳本）| 目標（新腳本）| 怎麼拿到 |
|------|-----------------|--------------|---------|
| Innovation 30% | 20 | 24 | 「K-pop 站姐文化搬格鬥」+「ONE 走了記憶還在」雙敘事 |
| Tech 30% | 18-22 | 24 | soulbound 正確實現 + Dynamic Field Table + Events + zkLogin + Walrus showcase |
| Impact 30% | 16-17 | 22 | 主線閉環可重播：check-in → 升級 → 守護 → 徽章 |
| Pitch 10% | 6-7 | 8 | 5 句核心敘事講完，不 buzzword 堆疊 |
| **總分** | **61-65** | **78** | |

---

## 溝通節奏

- **每日 15 分鐘站立會**（早上對齊進度 + blocker）
- **合約介面鎖定後不隨便改**（改動要雙方同意）
- **共享 Notion / GitHub Project 追 checklist**
- **Demo 腳本為王**：任何功能延伸要問「這幕 demo 會出現嗎？」，不會就砍

---

## 已砍掉的項目（勿復活清單）

這些項目經過 Codex 審查判定「工程成本高、評審感知低、會拖垮主流程」，勿在剩餘 72 小時內加回：

- YouTube / IG OAuth
- 社群帳號自動抓取上鏈
- Sponsored Transaction（gas 贊助）
- 法幣 → WAL 自動轉換
- 結帳掃碼模擬 + 假分潤
- POD 商城完整流程
- Content 合約（改用 mock + event）
- 內容按讚信號
- 二創授權流程
- Lv.3 完整人工蓋章流程
- 多拳手擴展
- 追蹤 / 通知 / 留言社交層

**如果時間還有剩，先加碼 Pitch 和 Demo 打磨，不是加回上述功能。**
