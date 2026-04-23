import { describe, it, expect, afterAll } from 'vitest'
import { buildTestApp } from '../helpers/build-test-app.js'

const app = await buildTestApp()
afterAll(async () => { await app.close() })

describe('GET /api/config', () => {
  it('returns pkg_id + mint_registry', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/config' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.network).toBe('testnet')
    expect(body.pkg_id).toMatch(/^0x/)
    expect(body.mint_registry.object_id).toMatch(/^0x/)
    expect(body.mint_registry.initial_shared_version).toBe('828957603')
  })
})
