import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

describe("webOS image cache fallback", () => {
  beforeEach(() => {
    vi.resetModules();
    vi.useFakeTimers();
    vi.stubGlobal("window", globalThis);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("loads the original image when IndexedDB remains pending", async () => {
    vi.doMock("../src/data/db", () => ({
      IMAGE_CACHE_MAX_BYTES: 16 * 1024 * 1024,
      IMAGE_CACHE_MAX_ENTRIES: 180,
      getDb: () => new Promise(() => {}),
      isQuotaExceededError: () => false,
      pruneImageCache: vi.fn(),
    }));
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      blob: async () => new Blob(["image"]),
    });
    vi.stubGlobal("fetch", fetchMock);
    vi.spyOn(URL, "createObjectURL").mockReturnValue("blob:direct-fallback");

    const { cachedImageURL, IMAGE_CACHE_READ_TIMEOUT_MS } = await import(
      "../src/services/imageCache"
    );
    const result = cachedImageURL("https://images.example/poster.jpg");
    await vi.advanceTimersByTimeAsync(IMAGE_CACHE_READ_TIMEOUT_MS);

    await expect(result).resolves.toBe("blob:direct-fallback");
    expect(fetchMock).toHaveBeenCalledWith(
      "https://images.example/poster.jpg", expect.objectContaining({ signal: expect.anything() }),
    );
  });
  it.each([false, true])("bounds stalled image downloads (body stalled: %s)", async bodyStalled => {
    vi.doMock("../src/data/db", () => ({
      getDb: async () => ({ get: async () => undefined }),
      isQuotaExceededError: () => false,
    }));
    const fetchMock = vi.fn().mockImplementation(() => bodyStalled
      ? Promise.resolve({ ok: true, blob: () => new Promise(() => {}) })
      : new Promise(() => {}));
    vi.stubGlobal("fetch", fetchMock);
    const { cachedImageURL, IMAGE_FETCH_TIMEOUT_MS } = await import("../src/services/imageCache");
    const url = "https://images.example/stalled.jpg";
    const pending = cachedImageURL(url);
    await vi.advanceTimersByTimeAsync(IMAGE_FETCH_TIMEOUT_MS);
    await expect(pending).resolves.toBe(url);
    expect(fetchMock.mock.calls[0][1].signal.aborted).toBe(true);
    await expect(cachedImageURL(url)).resolves.toBe(url);
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

});
