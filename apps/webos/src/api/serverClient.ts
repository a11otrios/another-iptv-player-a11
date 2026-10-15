import { CatalogKind, FavoriteKind, HistoryKind } from "../data/records";
import { discoverServers } from "./serverDiscovery";
import { SubtitleStylePreference } from "../data/settings";
import {
  clearCatalogStores,
  getDb,
  isQuotaExceededError,
} from "../data/db";

const CONNECTION_KEY = "aiptv.webos.server.v1";
const CONNECTION_BACKUP_KEY = "serverConnectionV1";
const CONNECTION_STORAGE_TIMEOUT_MS = 1500;
let relocationInFlight: Promise<ServerConnection | null> | null = null;
export const SERVER_REQUEST_TIMEOUT_MS = 15000;
const PLAYBACK_REQUEST_TIMEOUT_MS = 60000;

class ServerRequestTimeout extends Error {
  constructor() { super("Desktop server request timed out"); }
}

// Race the complete response, including its body. Chromium 53 has no
// AbortController; modern previews additionally cancel the underlying request.
async function fetchJson(
  url: string,
  init: RequestInit = {},
  timeoutMs = SERVER_REQUEST_TIMEOUT_MS,
): Promise<{ response: Response; body: any }> {
  const controller = typeof AbortController === "undefined" ? undefined : new AbortController();
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(new ServerRequestTimeout());
      controller?.abort();
    }, timeoutMs);
  });
  try {
    return await Promise.race([
      (async () => {
        const response = await fetch(url, { ...init, ...(controller ? { signal: controller.signal } : {}) });
        const body = response.status === 204 ? undefined : await response.json();
        return { response, body };
      })(),
      timeout,
    ]);
  } finally {
    clearTimeout(timer);
  }
}

export interface ServerConnection {
  baseUrl: string;
  token: string;
  deviceId: string;
  deviceName: string;
}

export interface ServerPlaylist {
  id: string;
  name: string;
  type: "xtream" | "m3u";
  createdAt: string;
}

export interface ServerCategory {
  id: string;
  name: string;
  type: string;
  hidden?: boolean;
}

export interface ServerItem {
  id: string | number;
  playlistId: string;
  type: CatalogKind;
  name: string;
  imageUrl?: string;
  categoryId?: string;
  epgChannelId?: string;
  rating?: string;
  genre?: string;
  plot?: string;
  releaseDate?: string;
  containerExtension?: string;
  createdAt?: string;
  lastModified?: string;
}

export interface ServerItemPage {
  items: ServerItem[];
  offset: number;
  limit: number;
  total: number;
  hasMore: boolean;
}

export interface ServerShelf {
  category: ServerCategory;
  items: ServerItem[];
  total: number;
}

export interface ServerSeries {
  id: string | number;
  name: string;
  imageUrl?: string;
  plot?: string;
  cast?: string;
  director?: string;
  genre?: string;
  rating?: string;
  releaseDate?: string;
  seasons: Array<{
    seasonNumber: number;
    episodes: Array<{
      id: string;
      title?: string;
      seasonNumber: number;
      episodeNumber: number;
      containerExtension?: string;
      plot?: string;
      durationMs?: number;
      imageUrl?: string;
    }>;
  }>;
}

export interface ServerVodDetails {
  plot?: string;
  cast?: string;
  director?: string;
  genre?: string;
  releaseDate?: string;
  rating?: string;
  backdropPath?: string[];
  youtubeTrailer?: string;
  duration?: string;
  durationSecs?: number;
  tmdbId?: string;
  containerExtension?: string;
}

export interface PlaybackDescriptor {
  mode: "proxy" | "hls" | "remux" | "transcode";
  url: string;
  mimeType: string;
  isLive: boolean;
  startPositionMs: number;
  expiresAt: string;
}

export interface ServerEpgProgram {
  id: string;
  title: string;
  description?: string;
  startTime?: string;
  endTime?: string;
  nowPlaying?: boolean;
}

export interface ServerSubtitleResult {
  fileId: number;
  subtitleId: string;
  language: string;
  title: string;
  releaseName: string;
  format: string;
  hearingImpaired: boolean;
  downloadCount: number;
  rating?: number;
}

export interface ServerSubtitleDescriptor {
  url: string;
  title: string;
  language: string;
  offsetMs: number;
  expiresAt: string;
}

export interface ServerSubtitleIdentity {
  playlistId: string;
  type: CatalogKind;
  itemId: string;
  episodeId?: string;
  title: string;
  season?: number;
}

export interface ServerPreferences {
  hiddenCategories: string[];
  hideRadioStations?: boolean;
  audioLanguage?: string;
  subtitleLanguage?: string;
  subtitleStyle?: SubtitleStylePreference;
}

export type ServerPreferencePatch = Partial<
  Pick<ServerPreferences, "hiddenCategories" | "hideRadioStations" | "audioLanguage" | "subtitleLanguage">
>;

interface Envelope<T> {
  apiVersion: number;
  data: T;
  error?: { code: string; message: string };
}

export function normalizeServerUrl(value: string): string {
  let url = value.trim();
  if (!/^https?:\/\//i.test(url)) url = `http://${url}`;
  url = url.replace(/\/+$/, "");
  if (!/\/api\/v1$/i.test(url)) url += "/api/v1";
  return url;
}

export function getServerConnection(): ServerConnection | null {
  try {
    const raw = localStorage.getItem(CONNECTION_KEY);
    if (!raw) return null;
    const value = JSON.parse(raw) as ServerConnection;
    return value.baseUrl && value.token ? value : null;
  } catch {
    return null;
  }
}

export function clearServerConnection(): void {
  localStorage.removeItem(CONNECTION_KEY);
  void deleteServerConnectionBackup();
}

function validServerConnection(value: unknown): value is ServerConnection {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Partial<ServerConnection>;
  return Boolean(candidate.baseUrl && candidate.token);
}

function withStorageTimeout<T>(operation: Promise<T>): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("Connection backup storage timed out")),
      CONNECTION_STORAGE_TIMEOUT_MS,
    );
    operation.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (error) => {
        clearTimeout(timer);
        reject(error);
      },
    );
  });
}

async function backupServerConnection(
  connection: ServerConnection,
): Promise<void> {
  try {
    const db = await withStorageTimeout(getDb());
    await withStorageTimeout(db.put("appState", {
      key: CONNECTION_BACKUP_KEY,
      value: connection,
    }));
  } catch {
    // The primary localStorage record already succeeded. A broken optional
    // backup must never prevent pairing, relocation, or application startup.
  }
}

async function deleteServerConnectionBackup(): Promise<void> {
  try {
    const db = await withStorageTimeout(getDb());
    await withStorageTimeout(db.delete("appState", CONNECTION_BACKUP_KEY));
  } catch {
    // Best-effort cleanup when the TV storage subsystem is unavailable.
  }
}

async function persistServerConnection(
  connection: ServerConnection,
): Promise<void> {
  const value = JSON.stringify(connection);
  try {
    localStorage.setItem(CONNECTION_KEY, value);
    await backupServerConnection(connection);
    return;
  } catch (error) {
    if (!isQuotaExceededError(error)) throw error;
  }

  const db = await getDb();
  await db.clear("imageCache");
  try {
    localStorage.setItem(CONNECTION_KEY, value);
    await backupServerConnection(connection);
    return;
  } catch (error) {
    if (!isQuotaExceededError(error)) throw error;
  }

  // Very old managed-client builds mirrored the full desktop catalog. It is
  // safe to discard only when every local playlist is desktop-managed; the
  // next sync recreates the small category index on demand.
  const playlists = await db.getAll("playlists");
  if (playlists.length > 0 && playlists.every((item) => item.managedByServer)) {
    await clearCatalogStores(db);
  }
  localStorage.setItem(CONNECTION_KEY, value);
  await backupServerConnection(connection);
}

export class ServerClient {
  constructor(private connection: ServerConnection) {}

  static async status(address: string): Promise<{ serverName: string }> {
    const baseUrl = normalizeServerUrl(address);
    const { response, body } = await fetchJson(`${baseUrl}/status`);
    if (!response.ok) throw new Error("Desktop server could not be reached");
    return body;
  }

  static async pair(address: string, code: string, deviceName = "LG TV"): Promise<ServerClient> {
    const baseUrl = normalizeServerUrl(address);
    const { response, body } = await fetchJson(`${baseUrl}/pair`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code, deviceName }),
    });
    if (!response.ok) throw new Error(body?.error?.message ?? "Pairing failed");
    const connection: ServerConnection = {
      baseUrl,
      token: body.token,
      deviceId: body.deviceId,
      deviceName: body.deviceName,
    };
    await persistServerConnection(connection);
    return new ServerClient(connection);
  }

  static connected(): ServerClient | null {
    const connection = getServerConnection();
    return connection ? new ServerClient(connection) : null;
  }

  static async restore(): Promise<ServerClient | null> {
    const current = getServerConnection();
    if (current) {
      void backupServerConnection(current);
      return new ServerClient(current);
    }
    try {
      const db = await withStorageTimeout(getDb());
      const backup = await withStorageTimeout(
        db.get("appState", CONNECTION_BACKUP_KEY),
      );
      if (!validServerConnection(backup?.value)) return null;
      localStorage.setItem(CONNECTION_KEY, JSON.stringify(backup.value));
      return new ServerClient(backup.value);
    } catch {
      return null;
    }
  }

  playlists(): Promise<ServerPlaylist[]> { return this.get("/playlists"); }
  categories(playlistId: string, type: CatalogKind): Promise<ServerCategory[]> {
    return this.get(`/categories?${query({ playlistId, type })}`);
  }
  items(playlistId: string, type: CatalogKind, options: {
    itemId?: string;
    categoryId?: string;
    query?: string;
    sort?: "release" | "releaseAscending" | "rating";
    offset?: number;
    limit?: number;
  } = {}): Promise<ServerItemPage> {
    return this.get(`/items?${query({ playlistId, type, ...options })}`);
  }
  async item(playlistId: string, type: CatalogKind, itemId: string | number): Promise<ServerItem | null> {
    return this.get(`/item?${query({ playlistId, type, itemId: String(itemId) })}`);
  }
  shelves(playlistId: string, type: CatalogKind, limit = 30): Promise<ServerShelf[]> {
    return this.get(`/shelves?${query({ playlistId, type, limit })}`);
  }
  async allItems(
    playlistId: string,
    type: CatalogKind,
    onProgress?: (loaded: number, total: number) => void,
  ): Promise<ServerItem[]> {
    const result: ServerItem[] = [];
    let offset = 0;
    for (;;) {
      const page = await this.items(playlistId, type, { offset, limit: 1000 });
      result.push(...page.items);
      onProgress?.(result.length, page.total);
      if (!page.hasMore) return result;
      offset += page.items.length;
    }
  }
  series(playlistId: string, seriesId: string | number): Promise<ServerSeries> {
    return this.get(`/series/${encodeURIComponent(String(seriesId))}?${query({ playlistId })}`);
  }
  vod(playlistId: string, vodId: string | number): Promise<ServerVodDetails> {
    return this.get(`/vod/${encodeURIComponent(String(vodId))}?${query({ playlistId })}`);
  }
  epg(playlistId: string, streamId: string, limit = 4): Promise<ServerEpgProgram[]> {
    return this.get(`/epg?${query({ playlistId, streamId, limit })}`);
  }
  shortcuts(playlistId: string, page = "A"): Promise<Record<string, { itemId: string; name: string; imageUrl?: string }>> {
    return this.get(`/shortcuts?${query({ playlistId, page })}`);
  }
  preferences(playlistId: string): Promise<ServerPreferences> {
    return this.get(`/preferences?${query({ playlistId })}`);
  }
  patchPreferences(playlistId: string, values: ServerPreferencePatch): Promise<ServerPreferences> {
    return this.request(`/preferences?${query({ playlistId })}`, {
      method: "PATCH",
      body: JSON.stringify(values),
    });
  }
  playback(
    playlistId: string,
    type: CatalogKind,
    itemId: string,
    episodeId?: string,
    modePreference?: "remux" | "transcode",
    startPositionMs?: number,
  ): Promise<PlaybackDescriptor> {
    return this.request("/playback", {
      method: "POST",
      body: JSON.stringify({
        playlistId,
        type,
        itemId,
        episodeId,
        modePreference,
        startPositionMs,
      }),
    });
  }
  releasePlayback(playbackUrl: string): Promise<void> {
    const sessionId = mediaSessionIdFromPlaybackUrl(
      playbackUrl,
      this.connection.baseUrl,
    );
    if (!sessionId) return Promise.resolve();
    return this.request(`/media/${encodeURIComponent(sessionId)}`, {
      method: "DELETE",
    });
  }
  searchSubtitles(identity: ServerSubtitleIdentity, queryText?: string, languages?: string): Promise<ServerSubtitleResult[]> {
    return this.request("/subtitles/search", {
      method: "POST",
      body: JSON.stringify({ ...identity, query: queryText, languages }),
    });
  }
  downloadSubtitle(identity: ServerSubtitleIdentity, result: ServerSubtitleResult): Promise<ServerSubtitleDescriptor> {
    return this.request("/subtitles/download", {
      method: "POST",
      body: JSON.stringify({ ...identity, result }),
    });
  }
  cachedSubtitle(identity: ServerSubtitleIdentity): Promise<ServerSubtitleDescriptor | null> {
    return this.get(`/subtitles/cached?${query({
      playlistId: identity.playlistId,
      type: identity.type,
      itemId: identity.itemId,
      episodeId: identity.episodeId,
    })}`);
  }
  setSubtitleOffset(identity: ServerSubtitleIdentity, offsetMs: number): Promise<{ offsetMs: number }> {
    return this.request("/subtitles/offset", {
      method: "PATCH",
      body: JSON.stringify({ ...identity, offsetMs }),
    });
  }
  favorites(playlistId: string): Promise<any[]> { return this.get(`/favorites?${query({ playlistId })}`); }
  history(playlistId: string): Promise<any[]> { return this.get(`/history?${query({ playlistId })}`); }
  clearHistory(playlistId: string): Promise<void> {
    return this.request(`/history?${query({ playlistId })}`, { method: "DELETE" });
  }
  putFavorite(playlistId: string, type: FavoriteKind, itemId: string, name: string, imageUrl?: string): Promise<any> {
    const wireType = type === "m3u" ? "live" : type;
    return this.request(`/favorites/${wireType}/${encodeURIComponent(itemId)}`, { method: "PUT", body: JSON.stringify({ playlistId, name, imageUrl, m3uItemId: type === "m3u" ? itemId : undefined }) });
  }
  deleteFavorite(playlistId: string, type: FavoriteKind, itemId: string): Promise<void> {
    const wireType = type === "m3u" ? "live" : type;
    return this.request(`/favorites/${wireType}/${encodeURIComponent(itemId)}?${query({ playlistId })}`, { method: "DELETE" });
  }
  putHistory(playlistId: string, type: HistoryKind, itemId: string, body: Record<string, unknown>): Promise<any> {
    return this.request(`/history/${type}/${encodeURIComponent(itemId)}`, { method: "PUT", body: JSON.stringify({ playlistId, ...body }) });
  }

  private get<T>(path: string): Promise<T> { return this.request(path); }
  private async request<T>(path: string, init: RequestInit = {}, allowRelocation = true): Promise<T> {
    let response: Response;
    let body: Envelope<T>;
    try {
      ({ response, body } = await fetchJson(`${this.connection.baseUrl}${path}`, {
        ...init,
        headers: { Authorization: `Bearer ${this.connection.token}`, "Content-Type": "application/json", ...init.headers },
      }, path === "/playback" ? PLAYBACK_REQUEST_TIMEOUT_MS : SERVER_REQUEST_TIMEOUT_MS));
    } catch (reason) {
      if (!allowRelocation) throw reason;
      // A timed-out write may already have succeeded; never replay it.
      if (reason instanceof SyntaxError ||
          (reason instanceof ServerRequestTimeout && (init.method ?? "GET") !== "GET")) throw reason;
      const relocated = await relocateConnection(this.connection);
      if (!relocated) throw reason;
      this.connection = relocated;
      return this.request(path, init, false);
    }
    if (response.status === 204) return undefined as T;
    if (!response.ok) throw new Error(body.error?.message ?? `Server request failed (${response.status})`);
    return body.data;
  }
}

export function mediaSessionIdFromPlaybackUrl(
  playbackUrl: string,
  serverBaseUrl: string,
): string | null {
  try {
    const playback = new URL(playbackUrl);
    const server = new URL(serverBaseUrl);
    if (playback.origin !== server.origin) return null;
    const apiPath = server.pathname.replace(/\/$/, "");
    const prefix = `${apiPath}/media/`;
    if (!playback.pathname.startsWith(prefix)) return null;
    const remainder = playback.pathname.slice(prefix.length);
    const separator = remainder.indexOf("/");
    if (separator <= 0 || remainder.slice(separator) !== "/index.m3u8") {
      return null;
    }
    return decodeURIComponent(remainder.slice(0, separator));
  } catch {
    return null;
  }
}

async function relocateConnection(connection: ServerConnection): Promise<ServerConnection | null> {
  if (relocationInFlight) return relocationInFlight;
  relocationInFlight = (async () => {
    const discovered = await discoverServers();
    const addressSet = new Set<string>();
    for (const server of discovered) {
      for (const address of server.addresses) addressSet.add(address);
    }
    const addresses = Array.from(addressSet);
    for (const address of addresses) {
      const baseUrl = normalizeServerUrl(address);
      try {
        const { response, body } = await fetchJson(`${baseUrl}/playlists`, {
          headers: {
            Authorization: `Bearer ${connection.token}`,
            "Content-Type": "application/json",
          },
        });
        if (!response.ok) continue;
        if (!Array.isArray(body.data)) continue;
        const relocated = { ...connection, baseUrl };
        await persistServerConnection(relocated);
        return relocated;
      } catch {
        // Try the next address advertised by discovery.
      }
    }
    return null;
  })();
  try {
    return await relocationInFlight;
  } finally {
    relocationInFlight = null;
  }
}

function query(values: Record<string, string | number | undefined>): string {
  const params = new URLSearchParams();
  Object.entries(values).forEach(([key, value]) => { if (value !== undefined) params.set(key, String(value)); });
  return params.toString();
}
