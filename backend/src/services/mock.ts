import stationsJson from '../mock-data/stations.json' with { type: 'json' }
import momentsJson from '../mock-data/moments.json' with { type: 'json' }
import fighterJson from '../mock-data/fighter-takeru.json' with { type: 'json' }
import videosJson from '../mock-data/videos.json' with { type: 'json' }

export type Hostess = { id: string; name: string; avatar_url: string; bio: string }
export type Station = {
  station_id: string
  event_name: string
  event_date: string
  venue: string
  hostesses: Hostess[]
}
export type MomentMeta = {
  moment_id: string
  title: string
  description: string
  video_url: string
  thumbnail_url: string
}
export type FighterProfile = {
  fighter_id: string
  name: string
  profile: { bio: string; career_record: string; championships: string[]; image_url: string }
}
export type Video = { id: string; title: string; url: string; thumbnail: string }

export type MockData = {
  stations: Station[]
  moments: MomentMeta[]
  fighter: FighterProfile
  videos: Video[]
}

let cached: MockData | null = null

export function loadMock(): MockData {
  if (cached) return cached
  cached = {
    stations: (stationsJson as { stations: Station[] }).stations,
    moments: (momentsJson as { moments: MomentMeta[] }).moments,
    fighter: fighterJson as FighterProfile,
    videos: (videosJson as { videos: Video[] }).videos,
  }
  return cached
}
