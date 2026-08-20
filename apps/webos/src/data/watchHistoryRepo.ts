import {
  AppDB,
  isQuotaExceededError,
} from "./db";
import { HistoryKind, WatchHistoryRecord } from "./records";
import { ServerClient } from "../api/serverClient";

export function historyId(
  playlistId: string,
  type: HistoryKind,
  streamId: string,
): string {
  return `${playlistId}_${type}_${streamId}`;
}

/**
 * Chooses the most useful position for a history checkpoint. Older webOS
 * video elements can emit an initial zero-valued timeupdate and then advance
 * their readable currentTime without emitting another event. Prefer that
 * live native clock whenever it is positive, retaining the last event value
 * only for short native-player transitions where currentTime resets to zero.
 */
export function resolveHistoryPositionMs(
  nativePositionMs: number,
  lastEventPositionMs: number,
  hasEventPosition: boolean,
): number {
  if (Number.isFinite(nativePositionMs) && nativePositionMs > 0) {
    return nativePositionMs;
  }
  if (
    hasEventPosition &&
    Number.isFinite(lastEventPositionMs) &&
    lastEventPositionMs > 0
  ) {
    return lastEventPositionMs;
  }
  return 0;
}

/**
 * Upserts a progress entry. Mirrors iOS rules: live entries carry zero
 * progress. VOD/series normally include duration, but older LG native-video
 * builds may report zero even while position advances. Preserve a resumable
 * position after the five-second threshold in that case.
 */
export async function saveProgress(
  db: AppDB,
  entry: Omit<WatchHistoryRecord, "id">,
): Promise<void> {
  if (
    entry.type !== "live" &&
    entry.durationMs <= 0 &&
    entry.lastTimeMs < 5000
  ) return;
  const record: WatchHistoryRecord = {
    ...entry,
    id: historyId(entry.playlistId, entry.type, entry.streamId),
    lastTimeMs: entry.type === "live" ? 0 : entry.lastTimeMs,
    durationMs: entry.type === "live" ? 0 : entry.durationMs,
  };
  const playlist = await db.get("playlists", entry.playlistId);
  const server = playlist?.managedByServer ? ServerClient.connected() : null;
  // Keep the responsive TV mirror even if the desktop becomes unreachable
  // after playback has started. The next successful desktop sync remains the
  // authority and will reconcile this record.
  let localError: unknown;
  try {
    await db.put("watchHistory", record);
  } catch (error) {
    if (!isQuotaExceededError(error)) {
      localError = error;
    } else {
      // Poster blobs are expendable and are the largest part of the TV cache.
      // A full webOS IndexedDB otherwise blocks tiny progress rows and, before
      // this retry, also prevented the authoritative desktop write below.
      await db.clear("imageCache").catch(() => {});
      try {
        await db.put("watchHistory", record);
      } catch (retryError) {
        localError = retryError;
      }
    }
  }

  let serverError: unknown;
  if (server) {
    try {
      await server.putHistory(entry.playlistId, entry.type, entry.streamId, {
        title: entry.title,
        seriesId: entry.seriesId == null ? undefined : String(entry.seriesId),
        imageUrl: entry.imageURL,
        positionMs: record.lastTimeMs,
        durationMs: record.durationMs,
      });
    } catch (error) {
      serverError = error;
    }
  }
  if (serverError) throw serverError;
  // Managed clients can continue from the authoritative desktop history even
  // when old webOS has made this origin's IndexedDB effectively read-only.
  if (localError && !server) throw localError;
}

export function getHistoryEntry(
  db: AppDB,
  playlistId: string,
  type: HistoryKind,
  streamId: string,
): Promise<WatchHistoryRecord | undefined> {
  return db.get("watchHistory", historyId(playlistId, type, streamId));
}

/**
 * Full history record for detail screens. Managed playlists prefer the
 * desktop authority because older webOS origins can become effectively
 * read-only after exceeding their IndexedDB quota; local history remains the
 * offline fallback.
 */
export async function getHistoryEntryWithServerFallback(
  db: AppDB,
  playlistId: string,
  type: HistoryKind,
  streamId: string,
  managedByServer: boolean,
): Promise<WatchHistoryRecord | undefined> {
  const local = await getHistoryEntry(db, playlistId, type, streamId);
  if (!managedByServer) return local;
  try {
    const entries = await ServerClient.connected()?.history(playlistId);
    const remote = entries?.find(
      (item: any) => item.type === type && String(item.itemId) === streamId,
    );
    if (!remote) return local;
    const positionMs = Number(remote.positionMs ?? 0);
    const durationMs = Number(remote.durationMs ?? 0);
    const parsedWatchedAt = Date.parse(String(remote.updatedAt ?? ""));
    return {
      id: historyId(playlistId, type, streamId),
      playlistId,
      type,
      streamId,
      lastTimeMs: Number.isFinite(positionMs) ? Math.max(0, positionMs) : 0,
      durationMs: Number.isFinite(durationMs) ? Math.max(0, durationMs) : 0,
      lastWatchedAt: Number.isFinite(parsedWatchedAt)
        ? parsedWatchedAt
        : local?.lastWatchedAt ?? Date.now(),
      title: String(remote.title ?? local?.title ?? ""),
      imageURL: remote.imageUrl ?? local?.imageURL,
      seriesId: remote.seriesId ?? local?.seriesId,
      secondaryTitle: local?.secondaryTitle,
      containerExtension: local?.containerExtension,
    };
  } catch {
    return local;
  }
}

/** Most recent first. */
export async function getRecentHistory(
  db: AppDB,
  playlistId: string,
  limit = 30,
): Promise<WatchHistoryRecord[]> {
  const results: WatchHistoryRecord[] = [];
  const range = IDBKeyRange.bound([playlistId], [playlistId, []]);
  let cursor = await db
    .transaction("watchHistory")
    .store.index("byPlaylistRecency")
    .openCursor(range, "prev");
  while (cursor && results.length < limit) {
    results.push(cursor.value);
    cursor = await cursor.continue();
  }
  return results;
}

export async function clearHistory(
  db: AppDB,
  playlistId: string,
): Promise<void> {
  const tx = db.transaction("watchHistory", "readwrite");
  const range = IDBKeyRange.bound([playlistId], [playlistId, []]);
  let cursor = await tx.store.index("byPlaylistRecency").openCursor(range);
  while (cursor) {
    await cursor.delete();
    cursor = await cursor.continue();
  }
  await tx.done;
}

/** Resume position for a vod/series item, or undefined if below threshold. */
export async function getResumePositionMs(
  db: AppDB,
  playlistId: string,
  type: HistoryKind,
  streamId: string,
): Promise<number | undefined> {
  if (type === "live") return undefined;
  const entry = await getHistoryEntry(db, playlistId, type, streamId);
  if (!entry || entry.lastTimeMs < 5000) return undefined;
  return entry.lastTimeMs;
}

/** Uses desktop history when a managed TV's local IndexedDB mirror is absent. */
export async function getResumePositionWithServerFallback(
  db: AppDB,
  playlistId: string,
  type: HistoryKind,
  streamId: string,
  managedByServer: boolean,
): Promise<number | undefined> {
  const local = await getResumePositionMs(db, playlistId, type, streamId);
  if (local !== undefined || !managedByServer || type === "live") return local;
  try {
    const entries = await ServerClient.connected()?.history(playlistId);
    const remote = entries?.find(
      (item: any) => item.type === type && String(item.itemId) === streamId,
    );
    const positionMs = Number(remote?.positionMs ?? 0);
    return Number.isFinite(positionMs) && positionMs >= 5000
      ? positionMs
      : undefined;
  } catch {
    return undefined;
  }
}

/**
 * A zero supplied by a Restart action is explicit and must win. Otherwise the
 * freshly persisted position wins over the snapshot captured when a detail
 * screen originally opened.
 */
export function chooseResumePositionMs(
  launchPositionMs: number | undefined,
  persistedPositionMs: number | undefined,
): number | undefined {
  if (launchPositionMs === 0) return 0;
  return persistedPositionMs ?? launchPositionMs;
}
