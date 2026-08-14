# webOS Architecture

## Design Goal

The LG application is a TV-focused client for the Windows desktop library. It
is not an independent IPTV account manager. This keeps provider credentials
off the TV and makes the desktop database the authoritative state shared by
Windows and webOS.

## Ownership

| Desktop owns | webOS owns |
| --- | --- |
| Provider credentials and playlist imports | Paired device identity/token |
| Full live, movie, and series catalogue | TV navigation and presentation |
| Category visibility and order | Small recoverable navigation cache |
| Per-category item sort order | Focus state and player overlay state |
| Radio visibility | LG lifecycle and remote events |
| Favorites and history | Native video/audio/text track access |
| Shortcut pages and assignments | Local rendering and artwork cache |
| EPG provider access and parsing | Temporary offline startup state |
| Playback URLs and provider headers | Per-stream presentation preferences |
| Proxy, remux, and transcode services | Subtitle rendering on the TV |

Desktop-owned values must win conflicts. The TV may use optimistic local state
for responsiveness but must reconcile it with the desktop.

## Startup and Synchronization

1. The TV reads a small saved server connection from `localStorage`.
2. It validates the paired bearer token against the desktop LAN server.
3. It fetches playlists, visible categories, preferences, favorites, and
   history.
4. Dashboard shelves are bounded samples. Full category contents are fetched
   in pages only when opened.
5. The TV writes favorite, history, and shared preference changes back to the
   desktop.
6. If the desktop address changes, LAN discovery can relocate a known paired
   server without exposing credentials.

The quota incident proved that full catalogue payloads must never be stored in
webOS `localStorage`. IndexedDB caches must remain bounded and disposable.

## Playback Flow

1. The TV sends an opaque playlist/type/item identity to `POST /api/v1/playback`.
2. The desktop resolves the provider URL and returns a signed local descriptor.
3. The TV first uses LG's native `<video>` pipeline.
4. On failure it requests FFmpeg remux and then transcode as compatibility
   fallbacks.
5. Obsolete FFmpeg sessions are explicitly released when switching, retrying,
   or leaving the player.

The upstream URL and credentials never enter the TV catalogue or API response.
See the protocol document for endpoint details.

## Native LG Boundary

The physical TV runs webOS 4.4 with Chromium 53. The application therefore
ships legacy-compatible JavaScript and avoids depending on modern browser
features without fallbacks.

LG renders native video through a platform media surface. CSS `object-fit` on
the `<video>` element does not control its aspect ratio on this hardware. The
current fit/crop/stretch state changes and persists, but the physical picture
does not change. The TV's own Picture settings are the reliable workaround.

The project uses `lennylxx/webos-iptv-player` as an LG playback and lifecycle
reference. It does not define this project's client/server data architecture.

## Storage

- `localStorage`: server connection, device identity, and small preferences.
- IndexedDB: recoverable playlists/categories index, favorites/history mirror,
  and bounded artwork metadata/cache.
- Desktop Drift database: authoritative catalogue and synchronized state.
- Desktop filesystem: temporary FFmpeg sessions and subtitle cache.

Quota errors must identify which store failed. Recovery may clear catalogue or
image caches, but must preserve the pairing connection and user-owned state.

## Key Source Boundaries

- API client: `apps/webos/src/api/serverClient.ts`
- IndexedDB: `apps/webos/src/data/db.ts`
- Image cache: `apps/webos/src/services/imageCache.ts`
- Dashboard: `apps/webos/src/ui/screens/DashboardScreen.tsx`
- Player: `apps/webos/src/ui/screens/PlayerScreen.tsx`
- LG adapter: `apps/webos/src/player/WebOSVideoAdapter.ts`
- Desktop LAN API: `apps/flutter/lib/services/lan_server`
- Desktop repository: `apps/flutter/lib/repositories/iptv_repository.dart`
