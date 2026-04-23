import { describe, it, expect } from 'vitest'
import { loadMock } from '../../src/services/mock.js'

describe('mock service', () => {
  it('loads stations with 3 entries', () => {
    const m = loadMock()
    expect(m.stations.length).toBe(3)
    expect(m.stations[0]!.hostesses.length).toBeGreaterThan(0)
  })
  it('loads fighter takeru with profile', () => {
    const m = loadMock()
    expect(m.fighter.fighter_id).toBe('takeru')
    expect(m.fighter.profile.championships.length).toBe(3)
  })
  it('loads moments metadata', () => {
    expect(loadMock().moments.length).toBe(3)
  })
})
