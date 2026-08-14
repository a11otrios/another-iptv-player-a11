import { ServerCategory, ServerClient, ServerItem } from "../api/serverClient";
import { CatalogSection } from "./catalogCache";
import { getCategories } from "./catalogRepo";
import { getDb } from "./db";
import {
  CatalogKind,
  CategoryRecord,
  LiveStreamRecord,
  PlaylistRecord,
  SeriesRecord,
  VodStreamRecord,
} from "./records";

export type ServerCatalogRecord = LiveStreamRecord | VodStreamRecord | SeriesRecord;

const sectionCache = new Map<string, Promise<CatalogSection>>();

export function serverItemToRecord(item: ServerItem, index = 0): ServerCatalogRecord {
  if (item.type === "live") {
    return { id: `${item.playlistId}_${item.id}`, playlistId: item.playlistId, streamId: item.id, name: item.name, icon: item.imageUrl, categoryId: item.categoryId, epgChannelId: item.epgChannelId, isAdult: false, sortIndex: index };
  }
  if (item.type === "vod") {
    return { id: `${item.playlistId}_${item.id}`, playlistId: item.playlistId, streamId: item.id, name: item.name, icon: item.imageUrl, categoryId: item.categoryId, rating: item.rating, containerExtension: item.containerExtension, added: item.createdAt, isAdult: false, sortIndex: index };
  }
  return { id: `${item.playlistId}_${item.id}`, playlistId: item.playlistId, seriesId: item.id, name: item.name, cover: item.imageUrl, plot: item.plot, genre: item.genre, releaseDate: item.releaseDate, rating: item.rating, categoryId: item.categoryId, lastModified: item.lastModified, seasonsLoaded: false, sortIndex: index };
}

function categoryRecord(playlistId: string, kind: CatalogKind, category: ServerCategory, index: number): CategoryRecord {
  return { id: `${playlistId}_${kind}_${category.id}`, playlistId, kind, categoryId: String(category.id), name: category.name, sortIndex: index };
}

export async function getServerCatalogSection(
  playlist: PlaylistRecord,
  kind: CatalogKind,
): Promise<CatalogSection> {
  const key = `${playlist.id}:${kind}`;
  const cached = sectionCache.get(key);
  if (cached) return cached;
  const request = loadServerCatalogSection(playlist, kind).catch((error) => {
    sectionCache.delete(key);
    throw error;
  });
  sectionCache.set(key, request);
  return request;
}

async function loadServerCatalogSection(
  playlist: PlaylistRecord,
  kind: CatalogKind,
): Promise<CatalogSection> {
  const client = ServerClient.connected();
  if (!client) throw new Error("Desktop server is not connected");
  const shelves = await client.shelves(playlist.id, kind);
  // The lightweight sync stores /categories in the exact desktop order.
  // Apply that index here as the client-side source of truth as well, so an
  // older /shelves response or a dashboard kept alive across sync cannot
  // silently revert to provider order.
  const syncedCategories = await getCategories(await getDb(), playlist.id, kind);
  const syncedOrder = new Map(
    syncedCategories.map((category, index) => [category.categoryId, index]),
  );
  const orderedShelves = shelves
    .map((shelf, index) => ({ shelf, index }))
    .sort((left, right) => {
      const leftOrder = syncedOrder.get(String(left.shelf.category.id));
      const rightOrder = syncedOrder.get(String(right.shelf.category.id));
      if (leftOrder !== undefined && rightOrder !== undefined) {
        return leftOrder - rightOrder;
      }
      if (leftOrder !== undefined) return -1;
      if (rightOrder !== undefined) return 1;
      return left.index - right.index;
    })
    .map(({ shelf }) => shelf);
  const categories: CategoryRecord[] = [];
  const items: ServerCatalogRecord[] = [];
  const byCategory = new Map<string, ServerCatalogRecord[]>();
  const categoryTotals = new Map<string, number>();
  orderedShelves.forEach((shelf, shelfIndex) => {
    const categoryId = String(shelf.category.id);
    categories.push(categoryRecord(playlist.id, kind, shelf.category, shelfIndex));
    const records = shelf.items.map((item, itemIndex) => serverItemToRecord(item, itemIndex));
    items.push(...records);
    byCategory.set(categoryId, records);
    categoryTotals.set(categoryId, shelf.total);
  });
  return { categories, items, byCategory, categoryTotals };
}

export function invalidateServerCatalog(playlistId?: string): void {
  if (playlistId === undefined) {
    sectionCache.clear();
    return;
  }
  for (const key of Array.from(sectionCache.keys())) {
    if (key.indexOf(`${playlistId}:`) === 0) sectionCache.delete(key);
  }
}
