import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ServerCategory, ServerClient, ServerItem } from "../src/api/serverClient";
import { bulkPut, getDb, resetDbForTests } from "../src/data/db";
import { PlaylistRecord } from "../src/data/records";
import {
  filterHiddenItems,
  serverSyncErrorKey,
  syncServerLibrary,
} from "../src/data/serverSync";
import { serverItemToRecord } from "../src/data/serverCatalog";

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  vi.stubGlobal("localStorage", {
    getItem: () => null,
    setItem: () => {},
    removeItem: () => {},
  });
  resetDbForTests();
});

describe("server catalog filtering", () => {
  it("preserves server timestamps used by recently-added ordering", () => {
    expect(serverItemToRecord({
      id: "movie",
      playlistId: "p",
      type: "vod",
      name: "Movie",
      createdAt: "1786233600",
    })).toEqual(expect.objectContaining({ added: "1786233600" }));
    expect(serverItemToRecord({
      id: "show",
      playlistId: "p",
      type: "series",
      name: "Show",
      lastModified: "1786233700",
    })).toEqual(expect.objectContaining({ lastModified: "1786233700" }));
  });
  it("does not cache items from hidden categories", () => {
    const categories: ServerCategory[] = [
      { id: "news", name: "News", type: "live" },
      { id: "adult", name: "Hidden", type: "live", hidden: true },
    ];
    const items: ServerItem[] = [
      { id: "1", playlistId: "p", type: "live", name: "News", categoryId: "news" },
      { id: "2", playlistId: "p", type: "live", name: "Hidden", categoryId: "adult" },
      { id: "3", playlistId: "p", type: "live", name: "Unsorted" },
    ];

    expect(filterHiddenItems(categories, items).map((item) => item.id)).toEqual([
      "1",
      "3",
    ]);
  });

  it("keeps the last good snapshot when a category refresh fails", async () => {
    const db = await getDb();
    const oldPlaylist: PlaylistRecord = {
      id: "p",
      name: "Cached library",
      type: "xtream",
      sourceType: "xtream",
      serverURL: "",
      username: "",
      password: "",
      filterAdultContent: false,
      createdAt: 1,
      managedByServer: true,
    };
    await db.put("playlists", oldPlaylist);
    await bulkPut(db, "liveStreams", [{
      id: "p_old",
      playlistId: "p",
      streamId: "old",
      name: "Cached channel",
      categoryId: "news",
      isAdult: false,
      sortIndex: 0,
    }]);

    const client = {
      playlists: async () => [{
        id: "p",
        name: "Remote library",
        type: "xtream" as const,
        createdAt: new Date(2).toISOString(),
      }],
      categories: async (_playlistId: string, kind: string) => {
        if (kind === "vod") throw new Error("desktop disconnected");
        return [];
      },
    } as unknown as ServerClient;

    const failure = await syncServerLibrary(client).catch((error) => error);
    expect(failure).toMatchObject({
      name: "ServerSyncError",
      stage: "categories",
      cause: expect.objectContaining({ message: "desktop disconnected" }),
    });
    expect(serverSyncErrorKey(failure)).toBe(
      "tv.desktop.sync_error.categories",
    );
    expect((await db.get("playlists", "p"))?.name).toBe("Cached library");
    expect((await db.getAll("liveStreams")).map((item) => item.name)).toEqual([
      "Cached channel",
    ]);
  });

  it("does not mirror the desktop item catalog during initial sync", async () => {
    let itemRequests = 0;
    const client = {
      playlists: async () => [{
        id: "p",
        name: "Remote library",
        type: "xtream" as const,
        createdAt: new Date(2).toISOString(),
      }],
      categories: async () => [],
      allItems: async () => { itemRequests += 1; return []; },
      favorites: async () => [{
        type: "vod",
        itemId: "outside-shelf",
        name: "Saved Movie",
        imageUrl: "https://images.invalid/saved.jpg",
        createdAt: new Date(3).toISOString(),
      }],
      history: async () => [{
        type: "vod",
        itemId: "outside-shelf",
        title: "Saved Movie",
        imageUrl: "https://images.invalid/saved.jpg",
        positionMs: 6000,
        durationMs: 60000,
        updatedAt: new Date(4).toISOString(),
      }],
      preferences: async () => ({ hiddenCategories: [] }),
    } as unknown as ServerClient;

    await syncServerLibrary(client);
    expect(itemRequests).toBe(0);
    const db = await getDb();
    expect(await db.get("favorites", "p_vod_outside-shelf")).toEqual(
      expect.objectContaining({
        name: "Saved Movie",
        imageURL: "https://images.invalid/saved.jpg",
      }),
    );
    expect(await db.get("watchHistory", "p_vod_outside-shelf")).toEqual(
      expect.objectContaining({ title: "Saved Movie", lastTimeMs: 6000 }),
    );
  });
});
