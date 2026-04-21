<img src="https://r2cdn.perplexity.ai/pplx-full-logo-primary-dark%402x.png" style="height:64px;margin-right:32px"/>

# 最後提出的這幾項idea，請分別提出使用sui network的理由，而不是使用傳統web2的解決方案

下面針對我們最後整理的四個方向，分別說明「為什麼要用 Sui，而不是只做一個 Web2 後端＋App」。重點會放在：**資產性／可組合性／多方信任與長期擴展性**，而不是單純「用區塊鏈比較酷」。

***

## 1. Campaign Compliance Studio（合規活動設計器）

### 為什麼要用 Sui

- **把「活動規則」變成可驗證的 on‑chain 合約，而不是 Excel 規格書**
    - 活動的參與條件、獎品上限、是否含預測等都寫成 Sui 上的對應 object / 合約，任何前端（官方 App、合作品牌小程式）都只能依這份規則發獎與抽獎，避免「行銷亂改玩法踩法規」。
    - Sui 的 object‑centric 模型非常適合把每個 campaign 當成獨立 object 管理，更新與審計成本小。[^1][^2]
- **多方信任：ONE、贊助商、甚至律所都可以讀同一套「活動真相」**
    - 傳統 Web2 是：行銷做一版、法務看 PDF、實作再寫成程式，三方狀態常常不同步。
    - 放在 Sui 上後，任何合作方都能檢查活動 config object，看到實際執行跟核准的規格是否一致，形成**單一真實來源**。
- **之後所有粉絲互動 app 可以直接重用同一份 campaign config**
    - 用 Web2 做，每個小遊戲／前端都要自己實作一遍規則。
    - 在 Sui 上，遊戲只要讀 campaign object，就能知道當前還有多少獎品 quota、活動是否已結束，減少錯誤，也讓新體驗可以「即插即用」。[^2][^3]

***

## 2. Fan Passport 2.0（粉絲身份與權益層）

### 為什麼要用 Sui

- **粉絲身份是「他自己的資產」，不是被 ONE 或 U‑NEXT 鎖住的帳號**
    - 傳統會員系統是中央資料庫，換平台就要重註冊；Sui 上的 Fan Passport 是獨立的 on‑chain object，可以跨 ONE App、U‑NEXT 活動頁、第三方合作社群工具共用。
    - Sui 的設計就是為大量資產物件（NFT / game item）提供高 TPS、低延遲與低 gas，非常適合高頻互動的粉絲場景。[^4][^3][^1][^2]
- **動態權益與成就可以「長成」一張資產，而不是散落在一堆資料表**
    - Sui 支援動態 NFT / object display，可隨著粉絲參與更新屬性（例如：已看 3 場 ONE Samurai → 升級外觀＋解鎖新權益）。[^5][^6][^4]
    - 這種「會進化的會員卡」在 Web2 通常需要很多後端 glue code，而在 Sui 上直接透過更新 object 狀態就能實現。
- **更順暢的 Web2 UX：zkLogin＋抽象錢包**
    - Sui 的 zkLogin 讓用戶用 Google / Apple 等 OAuth 帳號就能生成 Sui 帳戶，不用先學錢包、助記詞，對日本主流粉絲非常重要。[^7][^8]
    - 你可以在前端完全隱藏「區塊鏈」，但後台仍然是標準的 Sui 資產／交易，之後要接其他 Web3 生態（交易市場、二級體驗）也很容易。
- **方便和其他 Web3 項目互通**
    - 一旦粉絲護照在鏈上，之後如果 ONE 或贊助商想和其他 Sui dApp 聯名，只要讀取護照持有情況，就能做空投、白名單等合作，而不需要重新串每家廠商的私有 API。[^9][^2]

***

## 3. Samurai Arena Experiences（場館體驗 Pass 市場）

### 為什麼要用 Sui

- **體驗 Pass 本身是可組合的「實體體驗資產」**
    - 每個體驗（後台導覽、賽前彩排觀摩、VIP 区座位升級）都可以是一個 Sui object，包含時間、位置、可轉讓規則。
    - 這讓 ONE 能把同一個場館檔期切割成很多小產品，甚至讓贊助商購買並轉送給自己的客戶。Web2 也能做，但很容易變成一堆孤立的票種，難以跨平台流通。
- **支援即時、高頻的變更與查詢**
    - Sui 的高吞吐與低延遲可以讓「剩餘名額、場次狀態」這種資訊幾乎實時更新，現場臨時開放名額或改動也能馬上反映給所有前端（官方 App、票務合作方）。[^3][^10][^1][^2]
    - 傳統 Web2 若有多家票務與渠道，很容易出現 overbooking / 資料不同步的問題。
- **跨合作方的對帳與收入分配更透明**
    - 如果你把每張 Pass 的售價、折扣與歸屬（ONE / 場館 / 贊助商）部分寫在 Sui 合約裡，事後對帳和稽核就可以直接依賴鏈上紀錄。
    - 相對於多方各自的資料庫再對帳，省掉大量人工 reconciliation，對 ONE 與場館都是實際成本節省。
- **長期可以開放二級市場，但完全由 ONE 控制規則**
    - ON‑chain Pass 可以設定是否允許轉售、轉售價格上限、版稅分配等，這些邏輯寫進 Move 合約後就不容易被繞過，避免黃牛或違規轉售。Move 的資產安全模型天然適合這種不可複製、可控轉移的資產。[^11][^12][^2]

***

## 4. Samurai Fighter Hub（選手在日本的後勤 OS）

### 為什麼還要上 Sui（看起來很像純 B2B 內部系統）

- **跨公司、跨國界的共享資料層，比單一內部 DB 更實用**
    - 涉及選手行程的角色很多：ONE 日本辦公室、總部營運、經紀公司、當地健身房、醫療機構、甚至贊助商。
    - 若資訊只放在 ONE 的中心化 DB，其他方只能透過 API 或手動同步；放在 Sui 上，相關方可以在權限控制下讀取與更新同一套「行程與資源 object」，減少溝通成本。
- **資產與權限一體管理（Move 資源模型的優勢）**
    - 例如：
        - 某訓練場館的「可用時段」是一個 shared object，
        - 某位選手的「booking 權利」是另一個 object。
    - Move 的資源模型保證資產不能被複製或意外銷毀，讓「一個時段只能被一隊選手占用」這種約束自然成立，比起傳統 DB 需要大量鎖與檢查程式更安全。[^12][^1][^2][^11]
- **方便之後把「後勤資料」部分開放給粉絲體驗或贊助商產品**
    - 例如：某些 non‑sensitive 的 training log、到訪 dojo 數量可以被 Fan Passport 或贊助商活動引用（「跟著選手足跡巡禮」），因為資料已經是標準化的 Sui object。
    - 若用 Web2 內部系統，之後每做一個新體驗都要再開 API 或做資料匯出，反而增加工程負擔。
- **長期可導向 DAO / 治理與共創**
    - 如果 ONE 未來希望某些選手資源（例如共用訓練中心、獎學金計畫）有社群或贊助商共同治理，那這些資源與規則本來就在鏈上，轉成某種治理合約會比從 Web2 DB 遷移容易得多。[^2][^11]

***

## 簡單收斂

- **Campaign Compliance Studio**：Sui 讓「規則」變成可組合、可驗證的 on‑chain 資產，多方共享同一真相，避免活動實作與法務核准版本不一致。
- **Fan Passport 2.0**：Sui 提供真正的粉絲資產所有權、動態 NFT、跨平台互通與 zkLogin 友善登入，是打造「跨 ONE / U‑NEXT / 合作品牌」的粉絲身份層的最佳載體。[^1][^7][^4][^2]
- **Samurai Arena Experiences**：體驗 Pass 上鏈後可以細緻拆分場館時間、透明對帳、控制轉售規則，解決場地利用率與多方分潤問題。
- **Samurai Fighter Hub**：用 Sui 當多方共享的後勤狀態層與資產／權限系統，未來可以直接被粉絲／贊助商側的產品引用，避免內部系統變成黑盒。

如果你選定其中一個方向，我可以幫你再往下具體到：

- 要設計哪些 Sui object（結構、欄位、關係）
- Demo 裡哪些互動一定要「上鏈」，哪些可以先留在 Web2
- 在 Pitch 中如何用 1–2 句話把「為什麼一定要用 Sui」說得非常清楚。
<span style="display:none">[^13][^14][^15]</span>

<div align="center">⁂</div>

[^1]: https://www.gate.com/learn/articles/exploring-suis-object-centric-model-and-the-move-programming-language/4497

[^2]: https://allsparkresearch.com/research/sui-network/

[^3]: https://docs.sui.io/references/sui-compared

[^4]: https://suipiens.com/blog/what-makes-sui-become-the-gaming-heaven-for-projects/

[^5]: https://docs.sui.io/concepts/gaming

[^6]: https://www.blockchainappfactory.com/blog/sui-nft-ecosystem-explodes-what-it-means-for-gaming-and-real-world-assets/

[^7]: https://www.sui.io/zklogin

[^8]: https://github.com/NandyBa/sui-zklogin

[^9]: https://blog.sui.io/supporting-every-web3-gaming-type/

[^10]: https://www.binance.com/en/square/post/29446104631633

[^11]: https://x.com/ahboyash/status/2003838847696945486

[^12]: https://github.com/mystenlabs/sui

[^13]: https://www.linkedin.com/posts/emmanuel-abiodun_with-sui-network-walrus-protocol-seal-activity-7335290142628188161-z4vV

[^14]: https://blog.sui.io/eli-roths-the-horror-section/

[^15]: https://x.com/SuiNetwork/status/1967659819311173967

