import type { FastifyInstance } from 'fastify'
import { ConfigResponse } from '../schemas/config.js'

export async function configRoutes(app: FastifyInstance) {
  app.get(
    '/api/config',
    { schema: { response: { 200: ConfigResponse } } },
    async () => ({
      network: 'testnet' as const,
      pkg_id: app.config.PKG_ID,
      mint_registry: {
        object_id: app.config.MINT_REGISTRY_ID,
        initial_shared_version: app.config.MINT_REGISTRY_INITIAL_SHARED_VERSION,
      },
    }),
  )
}
