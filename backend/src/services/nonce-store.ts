import { Redis } from '@upstash/redis'

export type NonceStore = {
  claim: (nonce: string, ttlMs: number) => Promise<boolean>
  ping: () => Promise<boolean>
  kind: 'upstash' | 'memory'
}

export function createMemoryNonceStore(): NonceStore {
  const seen = new Map<string, number>()
  return {
    kind: 'memory',
    async claim(nonce, ttlMs) {
      const now = Date.now()
      const prev = seen.get(nonce)
      if (prev !== undefined && prev > now) return false
      seen.set(nonce, now + ttlMs)
      if (seen.size > 1000) {
        for (const [k, exp] of seen) if (exp <= now) seen.delete(k)
      }
      return true
    },
    async ping() { return true },
  }
}

export function createUpstashNonceStore(url: string, token: string): NonceStore {
  const redis = new Redis({ url, token })
  return {
    kind: 'upstash',
    async claim(nonce, ttlMs) {
      const ttlSec = Math.max(1, Math.ceil(ttlMs / 1000))
      const res = await redis.set(`nonce:${nonce}`, '1', { nx: true, ex: ttlSec })
      return res === 'OK'
    },
    async ping() {
      try { await redis.ping(); return true } catch { return false }
    },
  }
}
