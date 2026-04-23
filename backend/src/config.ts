import type { Env } from './env.js'
import { createSigner, type Signer } from './services/qr-signer.js'
import { createMemoryNonceStore, createUpstashNonceStore, type NonceStore } from './services/nonce-store.js'

export type Services = {
  signer: Signer
  nonceStore: NonceStore
  issuerTokens: Set<string>
}

export async function buildServices(env: Env): Promise<Services> {
  const signer = await createSigner({ current: env.QR_KEY_CURRENT, previous: env.QR_KEY_PREVIOUS })
  const useUpstash = env.NODE_ENV !== 'test' && env.UPSTASH_REDIS_REST_URL.startsWith('https://') && !env.UPSTASH_REDIS_REST_URL.includes('example.upstash.io')
  const nonceStore = useUpstash
    ? createUpstashNonceStore(env.UPSTASH_REDIS_REST_URL, env.UPSTASH_REDIS_REST_TOKEN)
    : createMemoryNonceStore()
  return {
    signer,
    nonceStore,
    issuerTokens: new Set(env.ISSUER_TOKENS),
  }
}
