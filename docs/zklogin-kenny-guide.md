# zkLogin 前端整合指南（Kenny 版）

**目標**：Google 登入 → 拿到 SUI address → 能簽 PTB 打我們的合約。

**Deadline**：2026-04-25 12:00 JST。若 zkLogin 卡住超過 6 小時，切備案 `@mysten/dapp-kit` 錢包連線（本文最後）。

---

## 0. 必備概念（30 秒）

zkLogin 流程 = **OAuth JWT + Ephemeral Keypair + ZK Proof** 三者組合：

1. 前端先產一把 **ephemeral keypair**（短期 Ed25519），並設定它可用到哪個 epoch (`maxEpoch`)
2. 把 ephemeral pubkey + maxEpoch + randomness 打成 **nonce**，塞進 Google OAuth request
3. Google 回傳 **JWT (`id_token`)**，裡面的 `nonce` 欄位就是你剛送的 nonce（防 replay）
4. 用 JWT + user salt 推出 **zkLogin SUI address**
5. 把 JWT + ephemeral pubkey + maxEpoch + salt 送給 **ZK Prover 服務**，拿回 ZK proof
6. 之後簽 tx：用 ephemeral keypair 對 tx 簽 Ed25519 → 把 `(proof, ephemeralSig, maxEpoch)` 打包成 zkLogin signature
7. 送 tx 到鏈上，合約 `tx_context::sender()` = zkLogin address

**合約這邊不用改任何東西。** Move 只看 sender，不管來源。

---

## 1. 套件安裝

```bash
npm install @mysten/sui
```

> 不要裝舊的 `@mysten/zklogin`（已併入 `@mysten/sui/zklogin`）。

需要的 imports：

```ts
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import {
  generateNonce,
  generateRandomness,
  getExtendedEphemeralPublicKey,
  jwtToAddress,
  genAddressSeed,
  getZkLoginSignature,
} from '@mysten/sui/zklogin';
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Transaction } from '@mysten/sui/transactions';
import { decodeJwt } from 'jose'; // 解 JWT 用
```

---

## 2. Google OAuth 設定

1. 進 [Google Cloud Console](https://console.cloud.google.com/apis/credentials)
2. Create OAuth 2.0 Client ID → **Web application**
3. Authorized redirect URIs 加：
   - `http://localhost:5173/auth/callback`（dev）
   - `https://ichimon-frontend.vercel.app/auth/callback`（prod）
4. 拿到 `Client ID`，放 `.env`：

```env
VITE_GOOGLE_CLIENT_ID=xxxxxxxxxxxx.apps.googleusercontent.com
VITE_ZKLOGIN_PROVER_URL=https://prover-dev.mystenlabs.com/v1
VITE_SUI_NETWORK=testnet
```

> hackathon 階段直接用 Mysten hosted prover (`prover-dev.mystenlabs.com`)，**不要自架**。

---

## 3. 登入流程 Step by Step

### Step 1 — 產 ephemeral keypair + nonce

`src/lib/zklogin/login.ts`:

```ts
import { SuiGrpcClient } from '@mysten/sui/grpc';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { generateNonce, generateRandomness } from '@mysten/sui/zklogin';

const client = new SuiGrpcClient({ network: 'testnet' });

export async function startLogin() {
  // 1. 查當前 epoch
  const { epoch } = await client.core.getReferenceGasPrice(); // 或 getLatestSuiSystemState()
  const maxEpoch = Number(epoch) + 2; // 這把 ephemeral key 最多用 2 個 epoch（~48h）

  // 2. 產 ephemeral keypair
  const ephemeralKeyPair = new Ed25519Keypair();

  // 3. 產 randomness + nonce
  const randomness = generateRandomness();
  const nonce = generateNonce(
    ephemeralKeyPair.getPublicKey(),
    maxEpoch,
    randomness
  );

  // 4. 存到 sessionStorage（不要用 localStorage — XSS 風險）
  sessionStorage.setItem('zk_ephemeral_sk', ephemeralKeyPair.getSecretKey());
  sessionStorage.setItem('zk_max_epoch', String(maxEpoch));
  sessionStorage.setItem('zk_randomness', randomness);

  // 5. 組 Google OAuth URL
  const params = new URLSearchParams({
    client_id: import.meta.env.VITE_GOOGLE_CLIENT_ID,
    redirect_uri: `${window.location.origin}/auth/callback`,
    response_type: 'id_token',
    scope: 'openid',
    nonce, // ← 關鍵：把 nonce 塞進去
  });

  window.location.href =
    `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}
```

### Step 2 — Callback：拿 JWT + 推 address

`src/pages/AuthCallback.tsx`:

```ts
import { decodeJwt } from 'jose';
import { jwtToAddress } from '@mysten/sui/zklogin';

export async function handleCallback() {
  // Google 把 id_token 放在 URL hash (response_type=id_token)
  const hash = new URLSearchParams(window.location.hash.slice(1));
  const jwt = hash.get('id_token');
  if (!jwt) throw new Error('No JWT in callback');

  // 拿 / 產 user salt
  const decoded = decodeJwt(jwt);
  const salt = getUserSalt(decoded.sub as string); // 見下方

  // 推 SUI address
  const address = jwtToAddress(jwt, salt);

  // 存 session
  sessionStorage.setItem('zk_jwt', jwt);
  sessionStorage.setItem('zk_salt', salt);
  sessionStorage.setItem('zk_address', address);

  return address;
}

// Hackathon 簡化：salt 寫死 or localStorage 存
// Production：要後端 salt service（保證同一 sub 永遠同一 salt）
function getUserSalt(sub: string): string {
  const key = `zk_salt_${sub}`;
  let salt = localStorage.getItem(key);
  if (!salt) {
    // 隨機產一個 16-byte BigInt 當 salt
    salt = String(BigInt('0x' + crypto.getRandomValues(new Uint8Array(16))
      .reduce((s, b) => s + b.toString(16).padStart(2, '0'), '')));
    localStorage.setItem(key, salt);
  }
  return salt;
}
```

> ⚠️ **salt 很重要**：同一個 Google 帳號，salt 換了 → address 換了 → 之前 mint 的 FanSBT 找不到！hackathon 用 localStorage 夠用但**清瀏覽器資料就會丟**。Demo 前不要清 cookie。

### Step 3 — 拿 ZK Proof（一次就好）

```ts
import { getExtendedEphemeralPublicKey } from '@mysten/sui/zklogin';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';

export async function fetchZkProof() {
  const jwt = sessionStorage.getItem('zk_jwt')!;
  const salt = sessionStorage.getItem('zk_salt')!;
  const maxEpoch = sessionStorage.getItem('zk_max_epoch')!;
  const randomness = sessionStorage.getItem('zk_randomness')!;
  const sk = sessionStorage.getItem('zk_ephemeral_sk')!;

  const keypair = Ed25519Keypair.fromSecretKey(sk);
  const extendedPk = getExtendedEphemeralPublicKey(keypair.getPublicKey());

  const res = await fetch(import.meta.env.VITE_ZKLOGIN_PROVER_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jwt,
      extendedEphemeralPublicKey: extendedPk,
      maxEpoch,
      jwtRandomness: randomness,
      salt,
      keyClaimName: 'sub',
    }),
  });

  if (!res.ok) throw new Error(`Prover error: ${res.status}`);
  const proof = await res.json();

  sessionStorage.setItem('zk_proof', JSON.stringify(proof));
  return proof;
}
```

> Prover 大約 3-10 秒回應，**UI 要有 loading**，不然以為當掉。

### Step 4 — 簽 & 送 tx

```ts
import {
  genAddressSeed,
  getZkLoginSignature,
} from '@mysten/sui/zklogin';
import { decodeJwt } from 'jose';
import { Transaction } from '@mysten/sui/transactions';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';

export async function signAndExecute(tx: Transaction) {
  const jwt = sessionStorage.getItem('zk_jwt')!;
  const salt = sessionStorage.getItem('zk_salt')!;
  const maxEpoch = sessionStorage.getItem('zk_max_epoch')!;
  const sk = sessionStorage.getItem('zk_ephemeral_sk')!;
  const proof = JSON.parse(sessionStorage.getItem('zk_proof')!);
  const address = sessionStorage.getItem('zk_address')!;

  tx.setSender(address);

  // 1. ephemeral keypair 簽 tx
  const keypair = Ed25519Keypair.fromSecretKey(sk);
  const { bytes, signature: userSignature } = await tx.sign({
    client,
    signer: keypair,
  });

  // 2. 組 address seed
  const decodedJwt = decodeJwt(jwt);
  const addressSeed = genAddressSeed(
    BigInt(salt),
    'sub',
    decodedJwt.sub as string,
    decodedJwt.aud as string,
  ).toString();

  // 3. 組 zkLogin signature
  const zkLoginSignature = getZkLoginSignature({
    inputs: { ...proof, addressSeed },
    maxEpoch,
    userSignature,
  });

  // 4. 送
  return await client.core.executeTransaction({
    transaction: bytes,
    signature: zkLoginSignature,
  });
}
```

---

## 4. 整合到我們的專案

### 4.1 Mint FanSBT（給初次登入用戶）

```ts
import { Transaction } from '@mysten/sui/transactions';

const CONFIG = await fetch('https://ichimon.fly.dev/api/config').then(r => r.json());
const PKG = CONFIG.pkg_id;          // v2 pkg for target
const REG = CONFIG.mint_registry;   // shared object + initial_shared_version

const tx = new Transaction();
tx.moveCall({
  target: `${PKG}::fan_sbt::mint_fan_card`,
  arguments: [
    tx.sharedObjectRef({
      objectId: REG.object_id,
      initialSharedVersion: REG.initial_shared_version,
      mutable: true,
    }),
    tx.pure.address(CONFIG.fighters.takeru.id),
  ],
});
const result = await signAndExecute(tx);
```

### 4.2 Check-in（`POST /api/checkin/qr/verify` 回 OK 後）

```ts
const tx = new Transaction();
tx.moveCall({
  target: `${PKG}::fan_sbt::record_check_in`,
  arguments: [
    tx.object(fanSbtId),            // 用戶自己的 SBT
    tx.pure.vector('u8', eventIdBytes),
  ],
});
await signAndExecute(tx);
```

其餘 PTB 範例見 `docs/frontend-integration-guide.md`。

---

## 5. 重點踩雷清單

| 雷區 | 症狀 | 解法 |
|------|------|------|
| salt 重新產生 | 用戶重登入後 address 變了，找不到 SBT | localStorage 存 `zk_salt_${sub}` |
| maxEpoch 過期 | `Ephemeral key expired` | 重跑登入流程（Step 1-3） |
| Prover timeout | fetch 掛 10+ 秒 | UI 加 loading；失敗重試 1 次 |
| `aud` 沒放進 addressSeed | `Invalid signature` | `genAddressSeed` 一定要帶 `decodedJwt.aud` |
| sessionStorage 在 redirect 掉 | callback 拿不到 ephemeralSK | 用 `sessionStorage` 跨 redirect 有效；**不要用** React state |
| nonce mismatch | Google 回來的 JWT nonce ≠ 送的 | 檢查 Step 1 的 nonce 有存、Step 2 沒覆蓋 |
| prover URL 打錯 | CORS / 404 | testnet 用 `https://prover-dev.mystenlabs.com/v1` |
| Gas 不夠 | tx 噴 `InsufficientGas` | zkLogin address 第一次用要先 faucet：`https://faucet.testnet.sui.io` 或用 CLI `sui client faucet --address <zk_addr>` |

---

## 6. 測試 checklist

1. [ ] Google 登入 → callback 拿到 address（console.log 看）
2. [ ] faucet 送 1 SUI 到該 address
3. [ ] Prover 回 proof（檢查 sessionStorage `zk_proof`）
4. [ ] 送一筆最簡單 tx（transfer 0.01 SUI 給自己），確認 zkLogin signature work
5. [ ] 打我們的 `mint_fan_card` PTB
6. [ ] 重新整理頁面 → 確認 session 還在、address 不變
7. [ ] 登出 → 重登 → address **必須相同**（salt 沒漏存）

---

## 7. 備案：`@mysten/dapp-kit` 錢包連線

若 4/25 早上 6 點還沒通，立刻切備案。產品敘事稍微弱（demo 要裝 Sui Wallet extension），但 20 分鐘可 work：

```bash
npm install @mysten/dapp-kit @mysten/sui @tanstack/react-query
```

```tsx
// App.tsx
import { SuiClientProvider, WalletProvider } from '@mysten/dapp-kit';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import '@mysten/dapp-kit/dist/index.css';

<QueryClientProvider client={new QueryClient()}>
  <SuiClientProvider networks={{ testnet: { url: 'https://fullnode.testnet.sui.io:443' } }} defaultNetwork="testnet">
    <WalletProvider autoConnect>
      <App />
    </WalletProvider>
  </SuiClientProvider>
</QueryClientProvider>
```

```tsx
// 任何 component
import { ConnectButton, useCurrentAccount, useSignAndExecuteTransaction } from '@mysten/dapp-kit';

const account = useCurrentAccount();
const { mutate: signAndExec } = useSignAndExecuteTransaction();

<ConnectButton />
// 有錢包後用 signAndExec({ transaction: tx })
```

Demo 腳本改一行：**「Google 登入 → 零門檻」** → **「Sui Wallet 一鍵連線，無需懂鑰匙」**。

---

## 8. 參考

- 官方教學：https://docs.sui.io/guides/developer/cryptography/zklogin-integration
- SDK 原始碼：https://github.com/MystenLabs/ts-sdks/tree/main/packages/typescript/src/zklogin
- Prover endpoint（testnet）：`https://prover-dev.mystenlabs.com/v1`
- 我們的合約介面：`docs/frontend-integration-guide.md`
- `/api/config`：https://ichimon.fly.dev/api/config
