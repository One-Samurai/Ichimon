import { Type } from '@sinclair/typebox'
import { Station } from './stations.js'

export const FighterResponse = Type.Object({
  fighter_id: Type.String(),
  name: Type.String(),
  profile: Type.Object({
    bio: Type.String(),
    career_record: Type.String(),
    championships: Type.Array(Type.String()),
    image_url: Type.String(),
  }),
  events: Type.Array(Station),
  videos: Type.Array(Type.Object({
    id: Type.String(),
    title: Type.String(),
    url: Type.String(),
    thumbnail: Type.String(),
  })),
  total_fans: Type.Optional(Type.Number()),
})

export const FighterParams = Type.Object({ id: Type.String() })
