import { AppDB } from "./db";
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
 * Upserts a progress entry. Mirrors iOS rules: live entries carry zero
 * progress; vod/series entries are only written once duration is known.
 */
export async function saveProgress(
  db: AppDB,
  entry: Omit<WatchHistoryRecord, "id">,
): Promise<void> {
  if (entry.type !== "live" && entry.durationMs <= 0) return;
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
  await db.put("watchHistory", record);
  if (server) {
    await server.putHistory(entry.playlistId, entry.type, entry.streamId, {
      title: entry.title,
      seriesId: entry.seriesId == null ? undefined : String(entry.seriesId),
      imageUrl: entry.imageURL,
      positionMs: record.lastTimeMs,
      durationMs: record.durationMs,
    });
  }
}

export function getHistoryEntry(
  db: AppDB,
  playlistId: string,
  type: HistoryKind,
  streamId: string,
): Promise<WatchHistoryRecord | undefined> {
  return db.get("watchHistory", historyId(playlistId, type, streamId));
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
