import { describe, it, expect, afterAll } from 'vitest'
import { buildTestApp } from '../helpers/build-test-app.js'

const app = await buildTestApp()
afterAll(async () => { await app.close() })

describe('GET /api/stations', () => {
  it('returns stations list from mock', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/stations' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.stations.length).toBe(3)
    expect(body.stations[0].hostesses.length).toBeGreaterThan(0)
  })
})
