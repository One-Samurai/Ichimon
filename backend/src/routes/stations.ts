import type { FastifyInstance } from 'fastify'
import { StationsResponse } from '../schemas/stations.js'
import { loadMock } from '../services/mock.js'

export async function stationsRoutes(app: FastifyInstance) {
  app.get(
    '/api/stations',
    { schema: { response: { 200: StationsResponse }, tags: ['read'] } },
    async () => ({ stations: loadMock().stations }),
  )
}
