// SuiService: thin wrapper over @mysten/sui SuiGrpcClient (v1.21.x).
//
// Per sui-ts-sdk skill the preferred high-level read path is
// `client.core.getObject({ objectId, include: { content: true, owner: true } })`.
// We use `any` casts defensively because the protobuf-derived response shape
// varies across minor SDK versions; this module is read-only and never feeds
// values back into transactions, so loose typing here is acceptable.
//
// POST-MVP: replace the shape-spelunking for registry.minted.size with a
// typed BCS decode once we codegen from the package ABI.

import { SuiGrpcClient } from '@mysten/sui/grpc'
import NodeCache from 'node-cache'
import { Errors } from '../errors.js'
import type { Env } from '../env.js'

export type SuiService = {
  client: SuiGrpcClient | null
  getMintRegistrySize: () => Promise<number>
  getObjectCached: <T>(id: string, ttlSec: number, fetcher: (raw: unknown) => T) => Promise<T>
  ping: () => Promise<boolean>
}

const TIMEOUT_MS = 5000

function withTimeout<T>(p: Promise<T>, ms = TIMEOUT_MS): Promise<T> {
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(Errors.chainTimeout()), ms)
    p.then(
      (v) => { clearTimeout(t); resolve(v) },
      (e) => { clearTimeout(t); reject(e) },
    )
  })
}

export function createSuiService(env: Env): SuiService {
  const client = new SuiGrpcClient({
    network: 'testnet',
    baseUrl: env.SUI_GRPC_URL,
  })
  const cache = new NodeCache({ stdTTL: 10, checkperiod: 30, useClones: false })

  async function fetchObject(id: string): Promise<unknown> {
    try {
      // Core API — recommended per sui-ts-sdk skill (SDK 1.21.x).
      const res = await withTimeout(
        (client as any).core.getObject({
          objectId: id,
          include: { content: true, owner: true },
        }),
      )
      return res
    } catch (e) {
      const msg = (e as Error)?.message ?? String(e)
      if (msg.includes('CHAIN_TIMEOUT')) throw e
      throw Errors.chainError(msg)
    }
  }

  // Walk a raw SDK object response and try to find `minted.size`.
  // Shape varies across SDK versions; inspect common nesting paths.
  function extractMintedSize(raw: any): number {
    const candidates = [
      raw?.object?.contents?.value?.minted?.size,
      raw?.object?.contents?.minted?.size,
      raw?.contents?.value?.minted?.size,
      raw?.contents?.minted?.size,
      raw?.data?.content?.fields?.minted?.fields?.size,
      raw?.data?.content?.fields?.minted?.size,
    ]
    for (const c of candidates) {
      if (c !== undefined && c !== null) return Number(c)
    }
    return 0
  }

  return {
    client,
    async getMintRegistrySize() {
      const key = `registry:size:${env.MINT_REGISTRY_ID}`
      const hit = cache.get<number>(key)
      if (hit !== undefined) return hit
      const raw = await fetchObject(env.MINT_REGISTRY_ID)
      const size = extractMintedSize(raw)
      cache.set(key, size)
      return size
    },
    async getObjectCached<T>(id: string, ttlSec: number, fetcher: (raw: unknown) => T): Promise<T> {
      const key = `obj:${id}`
      const hit = cache.get<T>(key)
      if (hit !== undefined) return hit
      const raw = await fetchObject(id)
      const parsed = fetcher(raw)
      cache.set(key, parsed, ttlSec)
      return parsed
    },
    async ping() {
      try {
        // getServiceInfo is not uniformly exposed; attempt a cheap noop.
        const info = (client as any).ledgerService?.getServiceInfo?.()
        if (info && typeof info.then === 'function') {
          await withTimeout(info, 2000)
        }
        return true
      } catch {
        return false
      }
    },
  }
}

export function createMockSuiService(): SuiService {
  return {
    client: null,
    async getMintRegistrySize() { return 0 },
    async getObjectCached<T>(_id: string, _ttl: number, fetcher: (raw: unknown) => T) {
      return fetcher({})
    },
    async ping() { return true },
  }
}
