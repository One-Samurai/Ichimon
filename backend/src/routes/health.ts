import type { FastifyInstance } from 'fastify'

export async function healthRoutes(app: FastifyInstance) {
  const startedAt = Date.now()
  app.get('/health', async () => ({
    ok: true,
    uptime: (Date.now() - startedAt) / 1000,
    version: process.env.npm_package_version ?? '0.0.0',
  }))

  app.get('/ready', async (_req, reply) => {
    const [nonce, sui] = await Promise.all([
      app.services.nonceStore.ping().catch(() => false),
      app.services.sui.ping().catch(() => false),
    ])
    const ok = nonce && sui
    if (!ok) return reply.status(503).send({ ok: false, nonce, sui })
    return { ok: true, nonce, sui }
  })
}
