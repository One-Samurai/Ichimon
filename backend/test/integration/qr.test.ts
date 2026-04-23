import { describe, it, expect, afterAll } from 'vitest'
import { buildTestApp } from '../helpers/build-test-app.js'

const app = await buildTestApp()
afterAll(async () => { await app.close() })

async function issue() {
  return app.inject({
    method: 'POST', url: '/api/checkin/qr/issue',
    payload: { station_id: 'st1', fighter_id: 'takeru', issuer_token: 'demo-1' },
  })
}

describe('POST /api/checkin/qr/issue', () => {
  it('returns payload + exp', async () => {
    const res = await issue()
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.qr_payload.split('.').length).toBe(3)
    expect(body.exp).toBeGreaterThan(Date.now())
  })
  it('rejects bad issuer_token', async () => {
    const res = await app.inject({
      method: 'POST', url: '/api/checkin/qr/issue',
      payload: { station_id: 'st1', fighter_id: 'takeru', issuer_token: 'nope' },
    })
    expect(res.statusCode).toBe(401)
    expect(res.json().error.code).toBe('UNAUTHORIZED')
  })
})

describe('POST /api/checkin/qr/verify', () => {
  it('issue → verify (200), verify again (409 NONCE_USED)', async () => {
    const r1 = await issue()
    const { qr_payload } = r1.json()
    const v1 = await app.inject({ method: 'POST', url: '/api/checkin/qr/verify', payload: { qr_payload } })
    expect(v1.statusCode).toBe(200)
    expect(v1.json().ok).toBe(true)
    const v2 = await app.inject({ method: 'POST', url: '/api/checkin/qr/verify', payload: { qr_payload } })
    expect(v2.statusCode).toBe(409)
    expect(v2.json().error.code).toBe('NONCE_USED')
  })
  it('malformed payload → MALFORMED_QR', async () => {
    const res = await app.inject({ method: 'POST', url: '/api/checkin/qr/verify', payload: { qr_payload: 'not.a.qr' } })
    expect(res.statusCode).toBe(400)
    expect(res.json().error.code).toBe('MALFORMED_QR')
  })
})
