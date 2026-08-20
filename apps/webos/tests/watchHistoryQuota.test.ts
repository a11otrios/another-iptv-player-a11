import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ServerClient } from "../src/api/serverClient";
import { getDb, resetDbForTests } from "../src/data/db";
import {
  getHistoryEntryWithServerFallback,
  getResumePositionMs,
  getResumePositionWithServerFallback,
  saveProgress,
} from "../src/data/watchHistoryRepo";

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  resetDbForTests();
  vi.restoreAllMocks();
});

async function addManagedPlaylist(): Promise<void> {
  const db = await getDb();
  await db.put("playlists", {
    id: "p",
    name: "Managed",
    type: "xtream",
    serverURL: "",
    username: "",
    password: "",
    filterAdultContent: false,
    createdAt: 1,
    managedByServer: true,
  });
}

const entry = {
  playlistId: "p",
  type: "vod" as const,
  streamId: "movie",
  lastTimeMs: 35_000,
  durationMs: 90_000,
  lastWatchedAt: 2,
  title: "Movie",
};

describe("watch-history quota recovery", () => {
  it("clears expendable posters and retries the local history row", async () => {
    await addManagedPlaylist();
    const db = await getDb();
    const putHistory = vi.fn(async () => undefined);
    vi.spyOn(ServerClient, "connected").mockReturnValue({
      putHistory,
    } as unknown as ServerClient);
    const originalPut = db.put.bind(db);
    let putAttempts = 0;
    vi.spyOn(db, "put").mockImplementation(((...args: Parameters<typeof db.put>) => {
      putAttempts += 1;
      if (putAttempts === 1) {
        return Promise.reject({ name: "QuotaExceededError" });
      }
      return originalPut(...args);
    }) as typeof db.put);
    const clear = vi.spyOn(db, "clear");

    await saveProgress(db, entry);

    expect(clear).toHaveBeenCalledWith("imageCache");
    expect(await getResumePositionMs(db, "p", "vod", "movie")).toBe(35_000);
    expect(putHistory).toHaveBeenCalledOnce();
  });

  it("still sends the checkpoint to the desktop if local recovery fails", async () => {
    await addManagedPlaylist();
    const db = await getDb();
    const putHistory = vi.fn(async () => undefined);
    vi.spyOn(ServerClient, "connected").mockReturnValue({
      putHistory,
    } as unknown as ServerClient);
    vi.spyOn(db, "put").mockRejectedValue({ name: "QuotaExceededError" });

    await expect(saveProgress(db, entry)).resolves.toBeUndefined();
    expect(putHistory).toHaveBeenCalledOnce();
  });

  it("reads a managed resume position from desktop history when local storage is absent", async () => {
    await addManagedPlaylist();
    const db = await getDb();
    const history = vi.fn(async () => [
      { type: "vod", itemId: "other", positionMs: 90_000 },
      { type: "vod", itemId: "movie", positionMs: 35_000 },
    ]);
    vi.spyOn(ServerClient, "connected").mockReturnValue({
      history,
    } as unknown as ServerClient);

    await expect(
      getResumePositionWithServerFallback(db, "p", "vod", "movie", true),
    ).resolves.toBe(35_000);
    expect(history).toHaveBeenCalledWith("p");
  });

  it("maps authoritative desktop history for the movie detail panel", async () => {
    await addManagedPlaylist();
    const db = await getDb();
    const history = vi.fn(async () => [
      {
        type: "vod",
        itemId: "movie",
        title: "Movie",
        imageUrl: "https://example.test/movie.jpg",
        positionMs: 35_000,
        durationMs: 90_000,
        updatedAt: "2026-08-15T22:30:00.000Z",
      },
    ]);
    vi.spyOn(ServerClient, "connected").mockReturnValue({
      history,
    } as unknown as ServerClient);

    const result = await getHistoryEntryWithServerFallback(
      db,
      "p",
      "vod",
      "movie",
      true,
    );

    expect(result).toMatchObject({
      id: "p_vod_movie",
      lastTimeMs: 35_000,
      durationMs: 90_000,
      title: "Movie",
      imageURL: "https://example.test/movie.jpg",
    });
    expect(result?.lastWatchedAt).toBe(
      Date.parse("2026-08-15T22:30:00.000Z"),
    );
  });
});
