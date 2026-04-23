import { Type } from '@sinclair/typebox'

export const Hostess = Type.Object({
  id: Type.String(),
  name: Type.String(),
  avatar_url: Type.String(),
  bio: Type.String(),
})

export const Station = Type.Object({
  station_id: Type.String(),
  event_name: Type.String(),
  event_date: Type.String(),
  venue: Type.String(),
  hostesses: Type.Array(Hostess),
})

export const StationsResponse = Type.Object({
  stations: Type.Array(Station),
})
