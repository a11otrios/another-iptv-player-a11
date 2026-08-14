import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { ServerClient } from "../src/api/serverClient";
import { getDb, resetDbForTests } from "../src/data/db";
import {
  chooseResumePositionMs,
  saveProgress,
} from "../src/data/watchHistoryRepo";

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  resetDbForTests();
  vi.restoreAllMocks();
});

describe("resume position selection", () => {
  it("prefers freshly persisted progress over a stale detail-screen snapshot", () => {
    expect(chooseResumePositionMs(10_000, 35_000)).toBe(35_000);
  });

  it("preserves an explicit restart from zero", () => {
    expect(chooseResumePositionMs(0, 35_000)).toBe(0);
  });

  it("keeps the newest local progress if the desktop write fails", async () => {
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
    vi.spyOn(ServerClient, "connected").mockReturnValue({
      putHistory: async () => {
        throw new Error("desktop unavailable");
      },
    } as unknown as ServerClient);

    await expect(
      saveProgress(db, {
        playlistId: "p",
        type: "vod",
        streamId: "movie",
        lastTimeMs: 35_000,
        durationMs: 90_000,
        lastWatchedAt: 2,
        title: "Movie",
      }),
    ).rejects.toThrow("desktop unavailable");
    expect(await db.get("watchHistory", "p_vod_movie")).toEqual(
      expect.objectContaining({ lastTimeMs: 35_000 }),
    );
  });
});
