import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, describe, expect, it } from "vitest";
import {
  getDb,
  isQuotaExceededError,
  pruneImageCache,
  resetDbForTests,
} from "../src/data/db";

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  resetDbForTests();
});

describe("webOS storage quota recovery", () => {
  it("prunes oldest poster blobs by both count and byte budget", async () => {
    const db = await getDb();
    for (let index = 1; index <= 3; index += 1) {
      const blob = new Blob([new Uint8Array(4)]);
      await db.put("imageCache", {
        url: `image-${index}`,
        blob,
        size: blob.size,
        lastUsedAt: index,
      });
    }

    await pruneImageCache(db, 2, 5);

    expect((await db.getAll("imageCache")).map((row) => row.url)).toEqual([
      "image-3",
    ]);
  });

  it("recognizes browser and legacy webOS quota errors", () => {
    expect(isQuotaExceededError({ name: "QuotaExceededError" })).toBe(true);
    expect(
      isQuotaExceededError({
        message: "An attempt was made to add storage that exceeded the quota.",
      }),
    ).toBe(true);
    expect(isQuotaExceededError(new Error("network unavailable"))).toBe(false);
  });
});

