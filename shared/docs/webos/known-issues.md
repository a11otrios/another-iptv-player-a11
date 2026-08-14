# webOS Known Issues

Last reviewed: 2026-08-11

Statuses describe evidence, not optimism. A source change is not resolved on
the physical TV until the correct desktop build or IPK is installed and tested.

## Active and Confirmed

| Priority | Issue | Evidence | Current workaround | Next action |
| --- | --- | --- | --- | --- |
| P1 | VOD/series resume does not persist on webOS | On webOS 1.7.10, native media time/duration advanced but no new local or desktop history row appeared after playback/Back | None | Move checkpointing into a webOS-native-safe mechanism and add a physical regression |
| P1 | In-app aspect ratio button has no visible effect | State and `object-fit` change, but LG native video ignores CSS aspect control | Use LG Picture > Aspect Ratio | Remove/disable the misleading control or design an explicit desktop-transcode solution |
| P1 | Build-folder desktop executable can be unreachable from TV | TV `/playlists` and `/shelves` stayed pending while localhost worked; installed path restored service | Run installed `Program Files` executable | Add/update explicit Firewall handling and deployment verification |
| P1 | Current EPG source fix may not be installed | Installed and release `data/app.so` hashes differed | Existing app remains usable; provider coverage varies | Install current desktop build properly, then retest |
| P2 | TV dashboard does not show Now/Next EPG on channel cards | TV requests EPG only after live playback starts | Open player/info; use desktop cards | Design a bounded/cached dashboard EPG strategy |
| P2 | Provider EPG coverage is partial | Sampled channels had current/future data, while recently viewed channels had only expired or empty schedules | No EPG for channels without current provider data | Distinguish unavailable, stale, and request-error states in UI |
| P2 | Windows artwork refresh reports need regression coverage | User reported favorites/history/category actions repeatedly refreshing icons | None confirmed | Reproduce with cache/network instrumentation and add widget regression tests |

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
- movie detail refreshes its resume time after returning from playback, and
  the player prefers freshly persisted progress over stale screen state.
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

The TV-side changes above are installed in webOS `1.7.10`; the supporting
desktop `1.7.1` installer is also installed. Do not remove an item from the
active table solely because a package exists. Move it only after the installed
binaries pass the relevant physical test.

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
