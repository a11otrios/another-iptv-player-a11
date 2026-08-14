# webOS Client/Server Protocol

This document defines the LAN contract between Another IPTV Player on the
desktop and the LG webOS client. The desktop database is authoritative for
playlists, catalog data, favorites, hidden categories, channel numbers, and
watch history. The TV owns only its device token and presentation preferences.

## Compatibility

- API base path: `/api/v1`
- JSON responses include `apiVersion: 1` where a top-level envelope is used.
- Unknown response fields must be ignored by clients.
- IDs are opaque strings. Clients must never infer an upstream URL from an ID.
- Times are UTC ISO-8601 strings; playback positions and durations are integer
  milliseconds.

## Pairing and authentication

`GET /api/v1/local/pairing` is a desktop-only diagnostic endpoint. Requests
whose peer address is not loopback receive `403`; local tooling can use it to
read the current six-digit code and expiry without exposing either value over
the LAN.

`GET /api/v1/status` is public and returns the server name, API version,
whether pairing is available, and the nullable `ffmpegAvailable` compatibility
capability. The desktop displays a six-digit, short-lived pairing code.

`POST /api/v1/pair`

```json
{
  "code": "123456",
  "deviceName": "Living Room TV"
}
```

The response contains a bearer token. All other API calls require
`Authorization: Bearer <token>`. Pairing codes are single-use. Device tokens
can be revoked from the desktop.

## Library endpoints

```text
GET /api/v1/playlists
GET /api/v1/categories?playlistId=&type=live|vod|series
GET /api/v1/shelves?playlistId=&type=&limit=
GET /api/v1/items?playlistId=&type=&categoryId=&query=&offset=&limit=
GET /api/v1/item?playlistId=&type=&itemId=
GET /api/v1/series/:id?playlistId=
GET /api/v1/vod/:id?playlistId=
GET /api/v1/epg?playlistId=&streamId=&from=&to=
GET /api/v1/search?playlistId=&query=&limit=
```

Playlist responses never expose provider credentials. Item responses contain
stable identity and display metadata but no provider URL.

Managed clients synchronize only playlists, visible categories, preferences,
favorites, and history. `shelves` returns a bounded sample and total count per
visible category for dashboard rendering. Full category contents remain on the
desktop and are read through offset pages; `item` supplies the base metadata
needed by movie and series detail screens. This prevents large providers from
copying six-figure catalogs into webOS IndexedDB.

## Synchronized state

```text
GET    /api/v1/favorites?playlistId=
PUT    /api/v1/favorites/:type/:itemId
DELETE /api/v1/favorites/:type/:itemId?playlistId=
GET    /api/v1/history?playlistId=
DELETE /api/v1/history?playlistId=
PUT    /api/v1/history/:type/:itemId
DELETE /api/v1/history/:type/:itemId?playlistId=
GET    /api/v1/preferences?playlistId=
PATCH  /api/v1/preferences?playlistId=
GET    /api/v1/shortcuts?playlistId=&page=A|S|D|F|G
```

State writes are idempotent and return the resulting record. The desktop
database remains the conflict winner; `updatedAt` is returned so later clients
can add optimistic synchronization without changing the contract.

Category responses follow the per-playlist, per-content-type order configured
by the desktop app. Categories not present in the saved order are appended in
provider order.

When `categoryId` and `query` are both supplied to `items`, the query is scoped
to item names inside that category. Without `categoryId`, search may also match
the containing category name.

The preference patch accepts `hiddenCategories`, `hideRadioStations`,
`audioLanguage`, and `subtitleLanguage`. Radio visibility is owned per playlist
by the desktop app for managed clients. TV track selections and the `__off__` subtitle sentinel are
written back so another TV or desktop playback session uses the same choice.

Shortcut pages use the same `A`, `S`, `D`, `F`, and `G` model as the desktop
player. Omitting `page` selects `A`; unsupported page names receive a validation
error. Each response maps numeric strings `0` through `9` to opaque live-item
identities and display metadata. On the TV, Yellow opens the live-channel
panel. Blue also opens it and cycles the active page while the panel is open;
the webOS-reserved More Actions (`...`) button is not part of the application
key contract.

## Playback

`POST /api/v1/playback` accepts an opaque item identity and returns a short
lived playback descriptor:

```json
{
  "playlistId": "...",
  "type": "live",
  "itemId": "...",
  "episodeId": null
}
```

```json
{
  "mode": "proxy",
  "url": "http://desktop:32145/api/v1/stream/opaque-ticket?...",
  "mimeType": "application/vnd.apple.mpegurl",
  "expiresAt": "2026-08-06T12:00:00Z",
  "isLive": true,
  "startPositionMs": 0
}
```

Supported modes are:

- `proxy`: the desktop forwards bytes, headers, ranges, and redirects.
- `hls`: the desktop rewrites manifests and serves segments through signed URLs.
- `remux`: FFmpeg remuxes an unsupported container to HLS without re-encoding.
- `transcode`: an explicit last resort for unsupported codecs.

FFmpeg modes return a session URL rooted at `/api/v1/media/:sessionId/`.
Authenticated clients should stop an obsolete session as soon as they switch
items, retry, advance to another fallback, or unmount the player:

```text
DELETE /api/v1/media/:sessionId
```

The server verifies that the session belongs to the calling device, terminates
its FFmpeg process, and deletes its temporary directory. A successful stop
returns `204`; an unknown, expired, or differently owned session returns `404`.

The server never returns the upstream URL, including when an older client sends
`preferDirect: true`. This invariant keeps Xtream credentials, signed provider
URLs, M3U tokens, and provider-specific headers on the desktop.

The TV selects playback through the native `<video>` pipeline following the
hardware-tested behavior documented by `lennylxx/webos-iptv-player`. hls.js and
mpegts.js are browser-preview fallbacks only. Native playback must preserve the
explicit MIME type, replace a wedged video element during recovery, and keep LG
audio/subtitle track handling behind the player adapter.

## Online subtitles

OpenSubtitles credentials remain on the desktop. The TV submits only an opaque
content identity and display title; downloaded files are cached by the desktop
and exposed as short-lived WebVTT links suitable for an HTML `<track>` element.

```text
POST  /api/v1/subtitles/search
POST  /api/v1/subtitles/download
GET   /api/v1/subtitles/cached?playlistId=&type=&itemId=&episodeId=
PATCH /api/v1/subtitles/offset
GET   /api/v1/subtitles/file/:ticket?access_token=
```

Media and subtitle URLs contain a separate short-lived random access grant,
never the paired device's bearer token. The server retains the device link in
memory, so revoking the device also invalidates grants that were already issued.

The download endpoint accepts one result returned by the search endpoint. Its
response contains `url`, `title`, `language`, `offsetMs`, and `expiresAt`.
Subtitle timing is clamped to +/-30 seconds and persisted with the desktop
cache record. SRT downloads are converted to WebVTT while being served.

### lennylxx reference boundary

The Apache-2.0 licensed `lennylxx/webos-iptv-player` is the compatibility
reference for LG-specific behavior, not the data architecture. In particular,
the client follows its native `<video>` approach, fresh-element recovery,
visibility suspend/resume behavior, asynchronous audio/text-track handling,
silent-stall detection, and remote-control conventions. Playlist credentials,
EPG processing, catalog management, transcoding, favorites, and history remain
desktop-server responsibilities in this project.

## Ownership

Desktop responsibilities:

- M3U/Xtream import and credential storage
- EPG parsing, refresh, indexing, and search
- catalog customization and parental filtering
- favorites, history, resume, and channel-number persistence
- provider-header normalization and optional proxy/remux/transcode

webOS responsibilities:

- remote and Magic Remote navigation
- TV-focused rendering and local presentation preferences
- LG lifecycle handling
- native playback, track selection, subtitles, and pipeline recovery
- resilient reconnect plus cached navigation/state for temporary outages
