import { beforeEach, describe, expect, it, vi } from "vitest";
import {
  mediaSessionIdFromPlaybackUrl,
  ServerClient,
  normalizeServerUrl,
} from "../src/api/serverClient";

const values = new Map<string, string>();
Object.defineProperty(globalThis, "localStorage", {
  value: {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  },
});

describe("desktop server client", () => {
  beforeEach(() => {
    values.clear();
    vi.restoreAllMocks();
  });

  it("normalizes a LAN address to the versioned API root", () => {
    expect(normalizeServerUrl("192.168.1.20:32145/"))
      .toBe("http://192.168.1.20:32145/api/v1");
    expect(normalizeServerUrl("https://tv.example/api/v1"))
      .toBe("https://tv.example/api/v1");
  });

  it("stores pairing credentials and authenticates later requests", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, json: async () => ({ token: "secret", deviceId: "tv1", deviceName: "LG TV" }) })
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ apiVersion: 1, data: [] }) });
    vi.stubGlobal("fetch", fetchMock);

    await ServerClient.pair("192.168.1.20:32145", "123456");
    const restored = ServerClient.connected();
    expect(restored).not.toBeNull();
    await restored!.playlists();

    expect(fetchMock.mock.calls[1][1].headers.Authorization).toBe("Bearer secret");
  });

  it("keeps OpenSubtitles credentials desktop-side", async () => {
    values.set("aiptv.webos.server.v1", JSON.stringify({
      baseUrl: "http://192.168.1.20:32145/api/v1",
      token: "secret",
      deviceId: "tv1",
      deviceName: "LG TV",
    }));
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ apiVersion: 1, data: [] }),
    });
    vi.stubGlobal("fetch", fetchMock);

    await ServerClient.connected()!.searchSubtitles({
      playlistId: "playlist-1",
      type: "series",
      itemId: "series-4",
      episodeId: "episode-9",
      title: "Example Show",
      season: 2,
    });

    const [, init] = fetchMock.mock.calls[0];
    expect(init.headers.Authorization).toBe("Bearer secret");
    expect(JSON.parse(init.body)).toEqual(expect.objectContaining({
      itemId: "series-4",
      episodeId: "episode-9",
      season: 2,
    }));
    expect(init.body).not.toContain("apiKey");
    expect(init.body).not.toContain("password");
  });

  it("fetches a single managed catalog item without downloading a page", async () => {
    values.set("aiptv.webos.server.v1", JSON.stringify({
      baseUrl: "http://192.168.1.20:32145/api/v1",
      token: "secret",
      deviceId: "tv1",
      deviceName: "LG TV",
    }));
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ apiVersion: 1, data: { id: "42", name: "Movie" } }),
    });
    vi.stubGlobal("fetch", fetchMock);

    await ServerClient.connected()!.item("playlist-1", "vod", "42");

    expect(fetchMock.mock.calls[0][0]).toBe(
      "http://192.168.1.20:32145/api/v1/item?playlistId=playlist-1&type=vod&itemId=42",
    );
  });

  it("requests the selected desktop channel-shortcut page", async () => {
    values.set("aiptv.webos.server.v1", JSON.stringify({
      baseUrl: "http://192.168.1.20:32145/api/v1",
      token: "secret",
      deviceId: "tv1",
      deviceName: "LG TV",
    }));
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ apiVersion: 1, data: {} }),
    });
    vi.stubGlobal("fetch", fetchMock);

    await ServerClient.connected()!.shortcuts("playlist-1", "S");

    expect(fetchMock.mock.calls[0][0]).toBe(
      "http://192.168.1.20:32145/api/v1/shortcuts?playlistId=playlist-1&page=S",
    );
  });

  it("releases only HLS compatibility sessions owned by the paired server", async () => {
    values.set("aiptv.webos.server.v1", JSON.stringify({
      baseUrl: "http://192.168.1.20:32145/api/v1",
      token: "secret",
      deviceId: "tv1",
      deviceName: "LG TV",
    }));
    const fetchMock = vi.fn().mockResolvedValue({ ok: true, status: 204 });
    vi.stubGlobal("fetch", fetchMock);

    await ServerClient.connected()!.releasePlayback(
      "http://192.168.1.20:32145/api/v1/media/session-42/index.m3u8?access_token=grant",
    );
    await ServerClient.connected()!.releasePlayback(
      "http://192.168.1.20:32145/api/v1/stream/ticket?access_token=grant",
    );

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock.mock.calls[0][0]).toBe(
      "http://192.168.1.20:32145/api/v1/media/session-42",
    );
    expect(fetchMock.mock.calls[0][1].method).toBe("DELETE");
    expect(mediaSessionIdFromPlaybackUrl(
      "http://other-host:32145/api/v1/media/session-42/index.m3u8",
      "http://192.168.1.20:32145/api/v1",
    )).toBeNull();
  });

  it("relocates a paired desktop after its LAN address changes", async () => {
    values.set("aiptv.webos.server.v1", JSON.stringify({
      baseUrl: "http://192.168.1.20:32145/api/v1",
      token: "secret",
      deviceId: "tv1",
      deviceName: "LG TV",
    }));
    vi.stubGlobal("window", {
      setTimeout,
      clearTimeout,
      webOS: {
        service: {
          request: (_uri: string, options: { onSuccess?: (response: unknown) => void }) => {
            options.onSuccess?.({
              servers: [{
                name: "Another IPTV Player",
                serverName: "desktop",
                addresses: ["http://192.168.1.44:32145"],
              }],
            });
          },
        },
      },
    });
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(new TypeError("network changed"))
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ apiVersion: 1, data: [] }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ apiVersion: 1, data: [] }),
      });
    vi.stubGlobal("fetch", fetchMock);

    await ServerClient.connected()!.playlists();

    expect(fetchMock.mock.calls.map((call) => call[0])).toEqual([
      "http://192.168.1.20:32145/api/v1/playlists",
      "http://192.168.1.44:32145/api/v1/playlists",
      "http://192.168.1.44:32145/api/v1/playlists",
    ]);
    expect(JSON.parse(values.get("aiptv.webos.server.v1")!).baseUrl)
      .toBe("http://192.168.1.44:32145/api/v1");
  });
});
