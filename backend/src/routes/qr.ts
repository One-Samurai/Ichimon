import type { FastifyInstance } from 'fastify'
import { QrIssueRequest, QrIssueResponse, QrVerifyRequest, QrVerifyResponse } from '../schemas/qr.js'
import { Errors } from '../errors.js'
import { loadMock } from '../services/mock.js'

export async function qrRoutes(app: FastifyInstance) {
  app.post<{ Body: { station_id: string; fighter_id: string; issuer_token: string } }>(
    '/api/checkin/qr/issue',
    {
      schema: { body: QrIssueRequest, response: { 200: QrIssueResponse }, tags: ['qr'] },
      config: { rateLimit: { max: 60, timeWindow: '1 minute' } },
    },
    async (req) => {
      const { station_id, fighter_id, issuer_token } = req.body
      if (!app.services.issuerTokens.has(issuer_token)) throw Errors.unauthorized()
      if (loadMock().fighter.fighter_id !== fighter_id) throw Errors.notFound('fighter')
      const exp = Date.now() + app.config.QR_EXPIRY_MS
      const qr_payload = await app.services.signer.sign({ station_id, fighter_id, exp })
      return { qr_payload, exp }
    },
  )

  app.post<{ Body: { qr_payload: string } }>(
    '/api/checkin/qr/verify',
    {
      schema: { body: QrVerifyRequest, response: { 200: QrVerifyResponse }, tags: ['qr'] },
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
    },
    async (req) => {
      const { payload } = await app.services.signer.verify(req.body.qr_payload)
      const fresh = await app.services.nonceStore.claim(payload.nonce, app.config.QR_EXPIRY_MS)
      if (!fresh) throw Errors.nonceUsed()
      return { ok: true as const, payload }
    },
  )
}
