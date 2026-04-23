import { Type } from '@sinclair/typebox'

export const ConfigResponse = Type.Object({
  network: Type.Literal('testnet'),
  pkg_id: Type.String(),
  mint_registry: Type.Object({
    object_id: Type.String(),
    initial_shared_version: Type.String(),
  }),
})
