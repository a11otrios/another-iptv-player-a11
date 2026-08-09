import { AppDB } from "../data/db";
import {
  PlaylistRecord,
  SeriesInfoEpisode,
  SeriesInfoRecord,
} from "../data/records";
import { getSeriesInfo, saveSeriesInfo } from "../data/seriesInfoRepo";
import { XtreamClient } from "../api/xtreamClient";
import { PlaybackUrlBuilder } from "../api/playbackUrlBuilder";
import {
  episodesBySeasonNumber,
  resolvedSeasons,
  XtreamSeriesInfo,
} from "../models/xtream";
import { PlayableItem } from "../models/playable";
import { ServerClient } from "../api/serverClient";

// Shared by the series detail screen and the continue-watching shelf (which
// jumps straight into playback, iOS HistorySeriesPlayerShell equivalent).

export function seriesInfoToRecord(
  playlistId: string,
  seriesId: string | number,
  remote: XtreamSeriesInfo,
): SeriesInfoRecord {
  const seasonsResolved = resolvedSeasons(remote);
  const buckets = episodesBySeasonNumber(remote);

  const seasons = seasonsResolved.map((season) => ({
    seasonNumber: season.number,
    name: season.metadata?.name,
    cover: season.metadata?.cover,
    overview: season.metadata?.overview,
    airDate: season.metadata?.airDate,
    episodeCount: season.metadata?.episodeCount,
  }));

  const flat: SeriesInfoEpisode[] = [];
  for (const season of seasonsResolved) {
    const bucket = buckets.get(season.number) ?? [];
    bucket.forEach((episode, position) => {
      if (episode.id === undefined) return;
      flat.push({
        id: episode.id,
        seasonNumber: season.number,
        episodeNum: episode.episodeNum ?? position + 1,
        title: episode.title,
        containerExtension: episode.containerExtension,
        plot: episode.info?.plot,
        cover: episode.info?.cover,
      });
    });
  }

  return {
    id: `${playlistId}_${seriesId}`,
    playlistId,
    seriesId,
    seasons,
    episodes: flat,
    fetchedAt: Date.now(),
  };
}

/**
 * Cached seasons/episodes, fetching (and persisting) from the panel when the
 * cache is empty — e.g. history entries for series whose detail screen was
 * never opened on this device. Returns null when the fetch fails too.
 */
export async function ensureSeriesInfo(
  db: AppDB,
  playlist: PlaylistRecord,
  seriesId: string | number,
): Promise<SeriesInfoRecord | null> {
  const cached = await getSeriesInfo(db, playlist.id, seriesId);
  // Empty responses can be transient (desktop offline, provider timeout, or
  // an older server that only exposed its local cache), so retry them.
  if (cached && cached.episodes.length > 0) return cached;
  try {
    if (playlist.managedByServer) {
      const client = ServerClient.connected();
      if (!client) return null;
      const remote = await client.series(playlist.id, seriesId);
      const record: SeriesInfoRecord = {
        id: `${playlist.id}_${seriesId}`,
        playlistId: playlist.id,
        seriesId,
        seasons: remote.seasons.map((season) => ({ seasonNumber: season.seasonNumber, episodeCount: season.episodes.length })),
        episodes: remote.seasons.flatMap((season) => season.episodes.map((episode) => ({
          id: episode.id,
          seasonNumber: episode.seasonNumber,
          episodeNum: episode.episodeNumber,
          title: episode.title,
          containerExtension: episode.containerExtension,
          plot: episode.plot,
          durationSecs: episode.durationMs ? Math.floor(episode.durationMs / 1000) : undefined,
          cover: episode.imageUrl,
        }))),
        fetchedAt: Date.now(),
      };
      try {
        await saveSeriesInfo(db, record);
      } catch (error) {
        console.warn("[series] could not cache managed series info", error);
      }
      return record;
    }
    const client = new XtreamClient(playlist);
    const remote = await client.getSeriesInfo(seriesId as number);
    const record = seriesInfoToRecord(playlist.id, seriesId, remote);
    await saveSeriesInfo(db, record);
    return record;
  } catch (error) {
    console.warn("[series] could not load series info", error);
    return null;
  }
}

/** Full episode queue in playback order (player resolves per-episode resume). */
export function buildSeriesQueue(
  playlist: PlaylistRecord,
  seriesId: string | number,
  seriesName: string,
  seriesCover: string | undefined,
  info: SeriesInfoRecord,
): PlayableItem[] {
  const urls = new PlaybackUrlBuilder(playlist);
  return info.episodes.map((entry) => ({
    url: playlist.managedByServer ? "" : urls.seriesUrl(entry.id, entry.containerExtension),
    title: seriesName,
    secondaryTitle: `S${entry.seasonNumber}E${entry.episodeNum}${entry.title ? ` · ${entry.title}` : ""}`,
    imageURL: entry.cover ?? seriesCover,
    isLive: false,
    historyType: "series" as const,
    historyStreamId: entry.id,
    seriesId,
    serverItemId: playlist.managedByServer ? String(seriesId) : undefined,
    serverEpisodeId: playlist.managedByServer ? entry.id : undefined,
    seasonNumber: entry.seasonNumber,
    containerExtension: entry.containerExtension,
  }));
}
