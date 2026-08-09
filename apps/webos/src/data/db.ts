import { DBSchema, IDBPDatabase, openDB } from "idb";
import {
  CategoryRecord,
  FavoriteRecord,
  LiveStreamRecord,
  M3UChannelRecord,
  PlaylistRecord,
  SeriesInfoRecord,
  SeriesRecord,
  VodInfoRecord,
  VodStreamRecord,
  WatchHistoryRecord,
} from "./records";

export const DB_NAME = "aiptv";
export const DB_VERSION = 2;

/** Disk tier of the image cache (posters/backdrops); pruned LRU. */
export interface ImageCacheRecord {
  url: string;
  blob: Blob;
  size: number;
  lastUsedAt: number;
}

export interface AppDBSchema extends DBSchema {
  playlists: {
    key: string;
    value: PlaylistRecord;
  };
  categories: {
    key: string;
    value: CategoryRecord;
    indexes: { byPlaylistKind: [string, string, number] };
  };
  liveStreams: {
    key: string;
    value: LiveStreamRecord;
    indexes: { byPlaylist: string; byPlaylistCategory: [string, string] };
  };
  vodStreams: {
    key: string;
    value: VodStreamRecord;
    indexes: { byPlaylist: string; byPlaylistCategory: [string, string] };
  };
  series: {
    key: string;
    value: SeriesRecord;
    indexes: { byPlaylist: string; byPlaylistCategory: [string, string] };
  };
  seriesInfo: {
    key: string;
    value: SeriesInfoRecord;
    indexes: { byPlaylist: string };
  };
  vodInfo: {
    key: string;
    value: VodInfoRecord;
    indexes: { byPlaylist: string };
  };
  m3uChannels: {
    key: string;
    value: M3UChannelRecord;
    indexes: { byPlaylist: string; byPlaylistGroup: [string, string] };
  };
  favorites: {
    key: string;
    value: FavoriteRecord;
    indexes: { byPlaylist: [string, number] };
  };
  watchHistory: {
    key: string;
    value: WatchHistoryRecord;
    indexes: { byPlaylistRecency: [string, number] };
  };
  imageCache: {
    key: string;
    value: ImageCacheRecord;
    indexes: { byLastUsed: number };
  };
}

export type AppDB = IDBPDatabase<AppDBSchema>;

export const IMAGE_CACHE_MAX_ENTRIES = 180;
export const IMAGE_CACHE_MAX_BYTES = 16 * 1024 * 1024;

let dbPromise: Promise<AppDB> | null = null;

export function getDb(): Promise<AppDB> {
  if (!dbPromise) {
    dbPromise = openDB<AppDBSchema>(DB_NAME, DB_VERSION, {
      upgrade(db, oldVersion) {
        if (oldVersion < 1) {
          db.createObjectStore("playlists", { keyPath: "id" });

          const categories = db.createObjectStore("categories", {
            keyPath: "id",
          });
          categories.createIndex("byPlaylistKind", [
            "playlistId",
            "kind",
            "sortIndex",
          ]);

          for (const name of ["liveStreams", "vodStreams", "series"] as const) {
            const store = db.createObjectStore(name, { keyPath: "id" });
            store.createIndex("byPlaylist", "playlistId");
            store.createIndex("byPlaylistCategory", [
              "playlistId",
              "categoryId",
            ]);
          }

          const seriesInfo = db.createObjectStore("seriesInfo", {
            keyPath: "id",
          });
          seriesInfo.createIndex("byPlaylist", "playlistId");

          const vodInfo = db.createObjectStore("vodInfo", { keyPath: "id" });
          vodInfo.createIndex("byPlaylist", "playlistId");

          const m3uChannels = db.createObjectStore("m3uChannels", {
            keyPath: "id",
          });
          m3uChannels.createIndex("byPlaylist", "playlistId");
          m3uChannels.createIndex("byPlaylistGroup", [
            "playlistId",
            "groupTitle",
          ]);

          const favorites = db.createObjectStore("favorites", {
            keyPath: "id",
          });
          favorites.createIndex("byPlaylist", ["playlistId", "addedAt"]);

          const watchHistory = db.createObjectStore("watchHistory", {
            keyPath: "id",
          });
          watchHistory.createIndex("byPlaylistRecency", [
            "playlistId",
            "lastWatchedAt",
          ]);
        }
        if (oldVersion < 2) {
          const imageCache = db.createObjectStore("imageCache", {
            keyPath: "url",
          });
          imageCache.createIndex("byLastUsed", "lastUsedAt");
        }
      },
    });
  }
  return dbPromise;
}

/** Test hook: forget the cached connection so a fresh DB can be opened. */
export function resetDbForTests(): void {
  dbPromise = null;
}

export type StoreWithPlaylistIndex =
  | "categories"
  | "liveStreams"
  | "vodStreams"
  | "series"
  | "seriesInfo"
  | "vodInfo"
  | "m3uChannels"
  | "favorites"
  | "watchHistory";

// Index used to find a playlist's rows, plus whether its key is compound
// ([playlistId, ...]) or the plain playlistId string. The range types differ:
// array-bounds never match string keys in IndexedDB's cross-type ordering.
const PLAYLIST_INDEX: Record<
  StoreWithPlaylistIndex,
  { name: string; compound: boolean }
> = {
  categories: { name: "byPlaylistKind", compound: true },
  liveStreams: { name: "byPlaylist", compound: false },
  vodStreams: { name: "byPlaylist", compound: false },
  series: { name: "byPlaylist", compound: false },
  seriesInfo: { name: "byPlaylist", compound: false },
  vodInfo: { name: "byPlaylist", compound: false },
  m3uChannels: { name: "byPlaylist", compound: false },
  favorites: { name: "byPlaylist", compound: true },
  watchHistory: { name: "byPlaylistRecency", compound: true },
};

export function playlistKeyRange(
  store: StoreWithPlaylistIndex,
  playlistId: string,
): IDBKeyRange {
  return PLAYLIST_INDEX[store].compound
    ? IDBKeyRange.bound([playlistId], [playlistId, []])
    : IDBKeyRange.only(playlistId);
}

/**
 * Deletes every row belonging to a playlist from the given stores.
 * Used by full refresh (content stores) and playlist deletion (all stores).
 */
export async function deletePlaylistRows(
  db: AppDB,
  playlistId: string,
  stores: StoreWithPlaylistIndex[],
): Promise<void> {
  // Collect primary keys first, then delete in chunked transactions: the old
  // awaited cursor.delete() round-trip per row made a 50k-row refresh crawl.
  for (const storeName of stores) {
    const keys = await db.getAllKeysFromIndex(
      storeName,
      PLAYLIST_INDEX[storeName].name as never,
      playlistKeyRange(storeName, playlistId),
    );
    const chunkSize = 2000;
    for (let i = 0; i < keys.length; i += chunkSize) {
      const tx = db.transaction(storeName, "readwrite");
      for (const key of keys.slice(i, i + chunkSize)) {
        void tx.store.delete(key);
      }
      await tx.done;
    }
  }
}

/** Fast migration path for server-only installs whose old mirrored catalog
 * can exceed webOS's quota before per-row IndexedDB deletes can commit. */
export async function clearCatalogStores(db: AppDB): Promise<void> {
  const stores: StoreWithPlaylistIndex[] = [
    "categories",
    "liveStreams",
    "vodStreams",
    "series",
    "seriesInfo",
    "vodInfo",
    "m3uChannels",
  ];
  for (const store of stores) await db.clear(store);
}

export function isQuotaExceededError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false;
  const value = error as { name?: string; code?: number; message?: string };
  return (
    value.name === "QuotaExceededError" ||
    value.code === 22 ||
    value.code === 1014 ||
    /quota|storage.*exceed/i.test(value.message ?? "")
  );
}

/** Keeps expendable poster blobs below a conservative webOS storage budget. */
export async function pruneImageCache(
  db: AppDB,
  maxEntries = IMAGE_CACHE_MAX_ENTRIES,
  maxBytes = IMAGE_CACHE_MAX_BYTES,
): Promise<void> {
  let entries = 0;
  let bytes = 0;
  let cursor = await db.transaction("imageCache").store.openCursor();
  while (cursor) {
    entries += 1;
    bytes += Math.max(0, cursor.value.size || cursor.value.blob.size || 0);
    cursor = await cursor.continue();
  }
  if (entries <= maxEntries && bytes <= maxBytes) return;

  const tx = db.transaction("imageCache", "readwrite");
  let oldest = await tx.store.index("byLastUsed").openCursor();
  while (oldest && (entries > maxEntries || bytes > maxBytes)) {
    bytes -= Math.max(0, oldest.value.size || oldest.value.blob.size || 0);
    entries -= 1;
    await oldest.delete();
    oldest = await oldest.continue();
  }
  await tx.done;
}

async function completeBulkPut<Name extends StoreWithPlaylistIndex>(
  db: AppDB,
  storeName: Name,
  records: AppDBSchema[Name]["value"][],
): Promise<void> {
  const tx = db.transaction(storeName, "readwrite");
  for (const record of records) void tx.store.put(record as never);
  await tx.done;
}

/** Bulk upsert in chunked transactions so huge catalogs don't starve the UI. */
export async function bulkPut<Name extends StoreWithPlaylistIndex>(
  db: AppDB,
  storeName: Name,
  records: AppDBSchema[Name]["value"][],
  chunkSize = 500,
  onProgress?: (written: number, total: number) => void,
): Promise<void> {
  for (let i = 0; i < records.length; i += chunkSize) {
    const chunk = records.slice(i, i + chunkSize);
    try {
      await completeBulkPut(db, storeName, chunk);
    } catch (error) {
      if (!isQuotaExceededError(error)) throw error;
      // Posters are disposable; catalog/state records are not. Clearing this
      // store also repairs TVs left full by older unbounded cache versions.
      await db.clear("imageCache");
      await completeBulkPut(db, storeName, chunk);
    }
    onProgress?.(Math.min(i + chunkSize, records.length), records.length);
  }
}
