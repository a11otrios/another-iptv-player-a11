import { useEffect, useState } from "react";
import {
  getDb,
  IMAGE_CACHE_MAX_BYTES,
  IMAGE_CACHE_MAX_ENTRIES,
  isQuotaExceededError,
  pruneImageCache,
} from "../data/db";

// Kingfisher-style two-tier image cache (iOS parity): an object-URL memory
// tier over an IndexedDB blob tier. IPTV panels rarely send cache headers,
// so without this every launch re-downloads every poster.

const MEMORY_MAX_ENTRIES = 500;
const MAX_SINGLE_IMAGE_BYTES = 2 * 1024 * 1024;
export const IMAGE_CACHE_READ_TIMEOUT_MS = 1500;
export const IMAGE_FETCH_TIMEOUT_MS = 8000;
// Rewriting lastUsedAt on every disk hit meant one IDB write per poster while
// scrolling — exactly when the main thread should stay idle. Recency only
// matters at prune granularity, so refresh it at most this often per row.
const TOUCH_MIN_MS = 6 * 60 * 60 * 1000;

const memory = new Map<string, string>(); // url → objectURL (insertion = LRU-ish)
const inflight = new Map<string, Promise<string>>();
// fetch() failed (offline panel, dev-browser CORS…) → fall back to the plain
// src for the rest of the session instead of re-failing per card.
const uncacheable = new Set<string>();
let pruneScheduled = false;
// IndexedDB on the physical webOS 4.4 TV can remain pending indefinitely
// after its quota ledger becomes unhealthy. Once that happens, bypass the
// optional disk tier for this app session so artwork can still load directly.
let diskCacheUnavailable = false;

function withTimeout<T>(operation: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error("Image cache storage timed out")),
      timeoutMs,
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

function remember(url: string, objectUrl: string): void {
  memory.set(url, objectUrl);
  if (memory.size > MEMORY_MAX_ENTRIES) {
    // Oldest entries are far off-screen by now; revoking frees the blob.
    const oldest = memory.keys().next().value as string | undefined;
    if (oldest !== undefined) {
      const stale = memory.get(oldest);
      memory.delete(oldest);
      if (stale) URL.revokeObjectURL(stale);
    }
  }
}

function schedulePrune(): void {
  if (pruneScheduled) return;
  pruneScheduled = true;
  window.setTimeout(() => {
    pruneScheduled = false;
    void prune();
  }, 5000);
}

async function prune(): Promise<void> {
  const db = await getDb();
  await pruneImageCache(
    db,
    IMAGE_CACHE_MAX_ENTRIES,
    IMAGE_CACHE_MAX_BYTES,
  );
}

async function cacheBlob(url: string, blob: Blob): Promise<void> {
  if (diskCacheUnavailable || blob.size > MAX_SINGLE_IMAGE_BYTES) return;
  const db = await getDb();
  try {
    await db.put("imageCache", {
      url,
      blob,
      size: blob.size,
      lastUsedAt: Date.now(),
    });
    schedulePrune();
  } catch (error) {
    if (!isQuotaExceededError(error)) return;
    // Free old-version caches immediately. The current image remains usable
    // from the in-memory object URL even when its disk write is discarded.
    await db.clear("imageCache").catch(() => {});
  }
}

async function resolve(url: string): Promise<string> {
  if (!diskCacheUnavailable) {
    try {
      const db = await withTimeout(getDb(), IMAGE_CACHE_READ_TIMEOUT_MS);
      const row = await withTimeout(
        db.get("imageCache", url),
        IMAGE_CACHE_READ_TIMEOUT_MS,
      );
      if (row) {
        // Touch for LRU (throttled); fire-and-forget.
        if (Date.now() - row.lastUsedAt > TOUCH_MIN_MS) {
          void db
            .put("imageCache", { ...row, lastUsedAt: Date.now() })
            .catch(() => {});
        }
        const objectUrl = URL.createObjectURL(row.blob);
        remember(url, objectUrl);
        return objectUrl;
      }
    } catch {
      diskCacheUnavailable = true;
    }
  }
  // Chromium 53 has no AbortController. Bound the complete download even
  // there; newer browsers also cancel the network request on timeout.
  const controller = typeof AbortController === "undefined" ? undefined : new AbortController();
  let blob: Blob;
  try {
    blob = await withTimeout((async () => {
      const response = controller ? await fetch(url, { signal: controller.signal }) : await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return response.blob();
    })(), IMAGE_FETCH_TIMEOUT_MS);
  } catch (error) {
    controller?.abort();
    throw error;
  }
  const objectUrl = URL.createObjectURL(blob);
  remember(url, objectUrl);
  void cacheBlob(url, blob);
  return objectUrl;
}

/** Cached object URL for an image; the original URL when caching fails. */
export function cachedImageURL(url: string): Promise<string> {
  const cached = memory.get(url);
  if (cached) {
    // True LRU: Map.set on an existing key does NOT move it to the end, so
    // hot posters could be evicted (and their object URLs revoked) while
    // cold ones survived. Re-insert to mark as most recently used.
    memory.delete(url);
    memory.set(url, cached);
    return Promise.resolve(cached);
  }
  if (uncacheable.has(url)) return Promise.resolve(url);
  const pending = inflight.get(url);
  if (pending) return pending;
  const promise = resolve(url)
    .catch(() => {
      uncacheable.add(url);
      return url;
    })
    .finally(() => inflight.delete(url));
  inflight.set(url, promise);
  return promise;
}

/**
 * React tier: resolves `src` through the cache while `active`. Returns
 * undefined until resolved (callers keep their placeholder up meanwhile).
 */
export function useCachedImage(
  src: string | undefined,
  active = true,
): string | undefined {
  const [resolved, setResolved] = useState<string | undefined>(undefined);
  useEffect(() => {
    // Drop the previous image immediately: keeping it while the new source
    // resolves briefly shows the WRONG artwork (e.g. detail screens flashing
    // the poster before the real backdrop arrives).
    setResolved(undefined);
    if (!src || !active) return;
    let cancelled = false;
    void cachedImageURL(src).then((url) => {
      if (!cancelled) setResolved(url);
    });
    return () => {
      cancelled = true;
    };
  }, [src, active]);
  return resolved;
}
