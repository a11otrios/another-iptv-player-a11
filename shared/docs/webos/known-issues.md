# webOS Known Issues

Last reviewed: 2026-08-15

Statuses describe evidence, not optimism. A source change is not resolved on
the physical TV until the correct desktop build or IPK is installed and tested.

## Source Fixes Awaiting Deployment: 2026-09-05

The current source removes the ineffective aspect control and addresses startup
storage hangs, stalled artwork downloads, HLS redirects, stream backpressure,
and discarded/late audio tracks. Audio selection now reports native state and
keeps failed selections out of saved preferences. These are locally validated
source changes, not claims of physical-TV resolution; see current-state.md.
Provider-origin outages and room-audio verification remain open.

## Active and Confirmed

| Priority | Issue | Evidence | Current workaround | Next action |
| --- | --- | --- | --- | --- |
| P1 | In-app aspect ratio button has no visible effect | State and `object-fit` change, but LG native video ignores CSS aspect control | Use LG Picture > Aspect Ratio | Remove/disable the misleading control or design an explicit desktop-transcode solution |
| P1 | Build-folder desktop executable can be unreachable from TV | TV `/playlists` and `/shelves` stayed pending while localhost worked; installed path restored service | Run installed `Program Files` executable | Add/update explicit Firewall handling and deployment verification |
| P1 | Current EPG source fix may not be installed | Installed and release `data/app.so` hashes differed | Existing app remains usable; provider coverage varies | Install current desktop build properly, then retest |
| P1 | Audible 4K playback still needs user confirmation | Final Wimpy Kid remux contains AAC-LC 5.1 and plays with `readyState=4`, but room audio cannot be observed through diagnostics; silence was reported on an earlier build | If silence remains, force compatibility audio to AAC stereo instead of stream-copy | Confirm sound at the TV, then either close this item or add audio-only transcode selection |
| P2 | TV dashboard does not show Now/Next EPG on channel cards | TV requests EPG only after live playback starts | Open player/info; use desktop cards | Design a bounded/cached dashboard EPG strategy |
| P2 | Provider EPG coverage is partial | Sampled channels had current/future data, while recently viewed channels had only expired or empty schedules | No EPG for channels without current provider data | Distinguish unavailable, stale, and request-error states in UI |
| P2 | Windows artwork refresh reports need regression coverage | User reported favorites/history/category actions repeatedly refreshing icons | None confirmed | Reproduce with cache/network instrumentation and add widget regression tests |
| P2 | Fresh TV dashboard artwork origin is unreachable | On 2026-09-04, 76/77 cards had valid image URLs; the external HTTP origin timed out from TV and desktop, and HTTPS also timed out | Previously cached blobs still render; initials remain as fallback | Recheck the external origin/provider and consider a desktop-owned artwork cache/proxy if outages persist |

## Physically Verified in webOS 1.7.16

- Backward seek recovery passed on the exact 4K MKV. Three Left presses moved
  the absolute UI clock from `1:50` to `1:34`; the native HLS clock moved from
  `73.096` to `57.861` and continued playing at `readyState=4`.
- VOD resume passed end to end: a desktop-managed checkpoint survived leaving
  playback, the detail screen offered the saved time, and native playback
  reopened at that position. The desktop fallback is required on the tested TV
  because its app origin returned IndexedDB `QuotaExceededError` even after
  disposable-cache cleanup.
- Movie Watch History physically rendered from the desktop-authoritative row
  on the exact 4K detail screen: `11:48 / 56:11`, a matching progress bar,
  `44:22` remaining, an app-locale watched timestamp, and separate Resume and
  Play From Start buttons all fit on the LG OLED55B8PLA screen.
- `EN - Diary Of A Wimpy Kid 4K (2021)` resumed from `36.433` seconds through
  HLS remux on the LG OLED55B8PLA. The media clock advanced normally with
  `readyState=4` and no error. Its generated stream contains native HEVC Main
  10 `3840x2160` video and AAC-LC 5.1 audio.
- The one-connection provider path passed random-access probing: overlapping
  FFmpeg Range requests are parked locally and serialized upstream, with
  provider keep-alive disabled. A redacted isolated trace successfully read
  the Matroska index range, returned to media data, and produced video/audio.

## Physically Verified in webOS 1.7.17

- A pending IndexedDB image-cache read no longer leaves eager dashboard
  artwork permanently in `waiting`; after the timeout, affected cards advance
  to direct network loading.
- Pairing recovery passed fault injection: after removing only the primary
  `localStorage` connection record and restarting, the IndexedDB backup
  restored it and the app opened the synchronized dashboard without pairing.

## Implemented but Requiring Continued Physical Regression

| Area | Current implementation | Risk to watch |
| --- | --- | --- |
| Pairing/sync quota | Lightweight sync plus quota recovery | Large providers and repeated repair cycles |
| TV artwork preload | Bounded active-row and grid preloading | Chromium 53 timing and memory pressure |
| Favorites | Desktop-authoritative writes and TV cache | Button feedback, failed writes, cross-device refresh |
| Category search | Global search matches items/categories; an open category searches only its items | Large result sets and hidden categories |
| Category order | Desktop order exported through LAN API | New provider categories and reset-to-original behavior |
| Per-category item sort | Persisted on desktop and used by shelves | Main panel refresh after sort changes |
| Radio hiding | Desktop per-playlist preference | Incorrect radio detection and stale TV preferences |
| Channel keys | Programme keys zap; D-pad navigates controls | LG firmware may reserve programme keys |
| Shortcut pages | Yellow opens channels; Blue cycles A/S/D/F/G; digits select | Page state and missing assignment behavior |
| EPG fallback | `get_short_epg`, then `get_simple_data_table`; expired entries filtered | Installed desktop may lag source; provider timestamp quality |

## Included in Current Release Artifacts; Physical Verification Pending

- repeated sync quota failure now runs a second disposable-catalog migration,
  bounds poster-cache bytes, and retries quota-failed writes after cleanup.
- Yellow opens the channel list during live playback; movie/episode Yellow
  continues to open track and subtitle settings.
- synced desktop category order refreshes mounted dashboards and orders
  shelves from the synchronized category index.
- category grids have category-scoped search and show existing star ratings.
- numeric shortcuts retain a programme-key queue made from the current live
  queue, live favorites, and the active shortcut page.
- webOS local-storage quota failure during pairing/sync.
- webOS image-cache quota recovery.
- artwork appearing only after focus on the channel/movie card.
- category-aware TV search.
- desktop-owned category sorting, move-to-top, and original-order reset.
- category item sort persistence and main-shelf refresh.
- channel switching while player controls are visible.
- dedicated programme up/down key handling.

The TV-side changes above are installed in webOS `1.7.16`; the physical
playback regression used the desktop source-tree release build. Do not remove
an item from the active table solely because a package exists. Move it only
after the installed binaries pass the relevant physical test.

## New Issue Template

```markdown
### Short issue title

- First observed:
- Desktop version and executable path:
- webOS version:
- TV model:
- Screen/content type:
- Reproduction steps:
- Expected:
- Observed:
- Does it reproduce after reopening the screen:
- Sanitized console/network evidence:
- Screenshot:
- Suspected ownership: desktop / LAN protocol / webOS UI / LG native player
- Test coverage needed:
- Status: reported / reproduced / source-fixed / packaged / installed / physically verified
```
