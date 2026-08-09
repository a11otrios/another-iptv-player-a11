import { ServerCategory, ServerClient, ServerItem } from "../api/serverClient";
import {
  bulkPut,
  clearCatalogStores,
  deletePlaylistRows,
  getDb,
  pruneImageCache,
} from "./db";
import { CatalogKind, CategoryRecord, PlaylistRecord } from "./records";
import { invalidateCatalog } from "./catalogCache";
import { settings } from "./settings";
import { invalidateServerCatalog } from "./serverCatalog";

export interface ServerSyncProgress {
  playlistName: string;
  kind: CatalogKind;
  loaded: number;
  total: number;
}

export type ServerSyncStage =
  | "connection"
  | "categories"
  | "state"
  | "preferences"
  | "storage";

export class ServerSyncError extends Error {
  constructor(
    readonly stage: ServerSyncStage,
    readonly cause: unknown,
  ) {
    super(`Desktop sync failed during ${stage}`);
    this.name = "ServerSyncError";
  }
}

export function serverSyncErrorKey(error: unknown): string {
  return error instanceof ServerSyncError
    ? `tv.desktop.sync_error.${error.stage}`
    : "tv.desktop.sync_error.unknown";
}

async function syncStage<T>(
  stage: ServerSyncStage,
  operation: () => Promise<T>,
): Promise<T> {
  try {
    return await operation();
  } catch (error) {
    if (error instanceof ServerSyncError) throw error;
    throw new ServerSyncError(stage, error);
  }
}

let activeSync: Promise<PlaylistRecord[]> | null = null;
const SERVER_CATALOG_MIGRATION_VERSION = 1;
const progressListeners = new Set<(progress: ServerSyncProgress) => void>();

export function syncServerLibrary(
  client: ServerClient,
  onProgress?: (progress: ServerSyncProgress) => void,
): Promise<PlaylistRecord[]> {
  if (onProgress) progressListeners.add(onProgress);
  if (!activeSync) {
    activeSync = performServerSync(client).finally(() => {
      activeSync = null;
      progressListeners.clear();
    });
  }
  return activeSync.finally(() => {
    if (onProgress) progressListeners.delete(onProgress);
  });
}

async function performServerSync(client: ServerClient): Promise<PlaylistRecord[]> {
  const db = await syncStage("storage", getDb);
  // Older builds allowed hundreds of unbounded poster blobs. Reclaim that
  // space before writing desktop state so quota failures self-heal on launch.
  await syncStage("storage", () => pruneImageCache(db));
  const remote = await syncStage("connection", () => client.playlists());
  const playlists: PlaylistRecord[] = remote.map((item) => ({
    id: item.id,
    name: item.name,
    type: "xtream",
    sourceType: item.type,
    serverURL: "",
    username: "",
    password: "",
    filterAdultContent: false,
    createdAt: Date.parse(item.createdAt) || Date.now(),
    managedByServer: true,
  }));

  const existing = await db.getAll("playlists");
  const remoteIds = new Set(playlists.map((item) => item.id));
  for (const stale of existing.filter((item) => item.managedByServer && !remoteIds.has(item.id))) {
    await syncStage("storage", async () => {
      await deletePlaylistRows(db, stale.id, ["categories", "liveStreams", "vodStreams", "series", "seriesInfo", "vodInfo", "m3uChannels", "favorites", "watchHistory"]);
      await db.delete("playlists", stale.id);
    });
  }

  for (const playlist of playlists) {
    await syncPlaylist(client, playlist);
    await syncStage("storage", () => db.put("playlists", playlist));
  }
  return playlists;
}

async function syncPlaylist(client: ServerClient, playlist: PlaylistRecord): Promise<void> {
  const db = await getDb();
  // Managed TVs retain the small navigation index; item pages stay on the
  // desktop and are fetched as shelves/categories are opened.
  const snapshots = await syncStage("categories", () =>
    Promise.all(
      (["live", "vod", "series"] as CatalogKind[]).map(async (kind) => ({
        kind,
        categories: await client.categories(playlist.id, kind),
      })),
    ),
  );

  await syncStage("storage", async () => {
    if (settings.serverCatalogMigrationVersion < SERVER_CATALOG_MIGRATION_VERSION) {
      const existing = await db.getAll("playlists");
      if (existing.length > 0 && existing.every((item) => item.managedByServer)) {
        await clearCatalogStores(db);
        // Chromium 53 can briefly reject new writes while reclaimed IndexedDB
        // pages are being accounted for after a large catalog clear.
        await new Promise((resolve) => setTimeout(resolve, 500));
      }
      settings.serverCatalogMigrationVersion = SERVER_CATALOG_MIGRATION_VERSION;
    }

    await deletePlaylistRows(db, playlist.id, ["categories", "liveStreams", "vodStreams", "series"]);
    for (const { kind, categories } of snapshots) {
      const visible = categories.filter((item) => !item.hidden);
      const categoryRows: CategoryRecord[] = visible.map((item, index) => ({
        id: `${playlist.id}_${kind}_${item.id}`,
        playlistId: playlist.id,
        kind,
        categoryId: String(item.id),
        name: item.name,
        sortIndex: index,
      }));
      await bulkPut(db, "categories", categoryRows);
    }
  });
  await Promise.all([
    syncStage("state", () => syncState(client, playlist.id)),
    syncStage("preferences", () => syncPreferences(client, playlist)),
  ]);
  invalidateCatalog(playlist.id);
  invalidateServerCatalog(playlist.id);
}

export function filterHiddenItems(
  categories: ServerCategory[],
  items: ServerItem[],
): ServerItem[] {
  const hiddenIds = new Set(
    categories.filter((category) => category.hidden).map((category) => String(category.id)),
  );
  if (hiddenIds.size === 0) return items;
  return items.filter(
    (item) => item.categoryId === undefined || !hiddenIds.has(String(item.categoryId)),
  );
}

async function syncPreferences(client: ServerClient, playlist: PlaylistRecord): Promise<void> {
  const preferences = await client.preferences(playlist.id);
  const normalizeLanguage = (value: string | undefined): string | null => {
    const normalized = value?.trim();
    return !normalized || normalized === "null" ? null : normalized;
  };
  settings.preferredAudioLanguage = normalizeLanguage(preferences.audioLanguage);
  settings.preferredSubtitleLanguage = normalizeLanguage(preferences.subtitleLanguage);
  if (preferences.subtitleStyle) settings.subtitleStyle = preferences.subtitleStyle;
  playlist.hideRadioStations = preferences.hideRadioStations === true;
}

async function syncState(client: ServerClient, playlistId: string): Promise<void> {
  const db = await getDb();
  const [favorites, history] = await Promise.all([client.favorites(playlistId), client.history(playlistId)]);
  await deletePlaylistRows(db, playlistId, ["favorites", "watchHistory"]);
  await bulkPut(db, "favorites", favorites.map((item: any) => ({ id: `${playlistId}_${item.type}_${item.itemId}`, playlistId, kind: item.type, itemId: String(item.itemId), addedAt: Date.parse(item.createdAt) || Date.now(), name: item.name, imageURL: item.imageUrl })));
  await bulkPut(db, "watchHistory", history.map((item: any) => ({ id: `${playlistId}_${item.type}_${item.itemId}`, playlistId, type: item.type, streamId: String(item.itemId), lastTimeMs: item.positionMs || 0, durationMs: item.durationMs || 0, lastWatchedAt: Date.parse(item.updatedAt) || Date.now(), title: item.title || "", imageURL: item.imageUrl, seriesId: item.seriesId })));
}
