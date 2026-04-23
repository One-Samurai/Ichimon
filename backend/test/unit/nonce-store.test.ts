import { describe, it, expect } from 'vitest'
import { createMemoryNonceStore } from '../../src/services/nonce-store.js'

describe('in-memory nonce store', () => {
  it('first claim returns true, second false', async () => {
    const s = createMemoryNonceStore()
    expect(await s.claim('abc', 1000)).toBe(true)
    expect(await s.claim('abc', 1000)).toBe(false)
  })
  it('entries expire after TTL', async () => {
    const s = createMemoryNonceStore()
    expect(await s.claim('t', 50)).toBe(true)
    await new Promise((r) => setTimeout(r, 80))
    expect(await s.claim('t', 50)).toBe(true)
  })
  it('concurrent claims — only one wins', async () => {
    const s = createMemoryNonceStore()
    const rs = await Promise.all(Array.from({ length: 100 }, () => s.claim('race', 1000)))
    expect(rs.filter(Boolean).length).toBe(1)
  })
})
