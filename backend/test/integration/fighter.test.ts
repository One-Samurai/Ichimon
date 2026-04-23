import { describe, it, expect, afterAll } from 'vitest'
import { buildTestApp } from '../helpers/build-test-app.js'

const app = await buildTestApp()
afterAll(async () => { await app.close() })

describe('GET /api/fighter/:id', () => {
  it('returns takeru profile', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/fighter/takeru' })
    expect(res.statusCode).toBe(200)
    const body = res.json()
    expect(body.fighter_id).toBe('takeru')
    expect(body.events.length).toBe(3)
    expect(body.videos.length).toBe(3)
  })
  it('404 for unknown fighter', async () => {
    const res = await app.inject({ method: 'GET', url: '/api/fighter/unknown' })
    expect(res.statusCode).toBe(404)
    expect(res.json().error.code).toBe('NOT_FOUND')
  })
})
