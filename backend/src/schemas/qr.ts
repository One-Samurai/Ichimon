import { Type } from '@sinclair/typebox'

export const QrIssueRequest = Type.Object({
  station_id: Type.String({ minLength: 1 }),
  fighter_id: Type.String({ minLength: 1 }),
  issuer_token: Type.String({ minLength: 1 }),
})

export const QrIssueResponse = Type.Object({
  qr_payload: Type.String(),
  exp: Type.Number(),
})

export const QrVerifyRequest = Type.Object({
  qr_payload: Type.String({ minLength: 1, maxLength: 4096 }),
})

export const QrVerifyResponse = Type.Object({
  ok: Type.Literal(true),
  payload: Type.Object({
    station_id: Type.String(),
    fighter_id: Type.String(),
    nonce: Type.String(),
    iat: Type.Number(),
    exp: Type.Number(),
  }),
})
