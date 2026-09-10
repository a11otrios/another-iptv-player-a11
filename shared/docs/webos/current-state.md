# webOS Current State

Last updated: 2026-09-04

This file records facts needed to resume safely. Verify volatile network and
process details before relying on them.

## Versions and Devices

| Component | State |
| --- | --- |
| Flutter desktop source | `1.7.1+32` |
| Windows installer artifact | `1.7.1` |
| Installed Windows desktop | `1.7.1+32` |
| webOS source/installed package | `1.7.17` |
| webOS app ID | `com.devyorg.anotheriptvplayer` |
| Physical TV | LG OLED55B8PLA, webOS 4.4 / Chromium 53 |
| CLI device name | `tv` |
| Desktop LAN server | TCP `32145`, UDP discovery `32146` |

The observed TV address was `192.168.1.168` and the desktop address was
`192.168.1.181`. Both are DHCP addresses and must be rechecked.

## Source Review Fixes: 2026-09-05 (Not Deployed)

- TV launch and playlist reads have bounded storage waits and retain recovery
  controls on failure. Image network requests, including body downloads, now
  time out and fall back to the original image URL.
- Desktop stream forwarding applies downstream backpressure while retaining
  cancellation for superseded FFmpeg requests. HLS relative references resolve
  against the final redirected manifest location.
- FFmpeg remux/transcode retains all audio tracks and their language metadata.
  The TV retries preferences when tracks arrive late, restores manual choices
  after native video recovery, and uses native selection state for checkmarks.
  A rejected selection leaves the previous audio track enabled and reports a
  failure instead of saving a false preference.
- Player controls expose separate Audio and Subtitle panels, keep selection
  feedback visible, and remove the ineffective CSS aspect button/Green shortcut.
  Existing saved aspect settings are preserved; use LG Picture settings.
- Validation: webOS unit tests and TypeScript/modern/Chromium-53 builds pass;
  desktop media/LAN tests and focused Dart analysis pass. Synthetic FFmpeg
  conversion retains German and English audio in both remux and transcode HLS.
  An isolated Edge check renders the actual player controls, checks manual
  audio selection feedback, and verifies startup recovery with hung IndexedDB.
- No installer, TV package installation, live app replacement, provider test,
  or physical-TV playback was performed. Audible native track switching and
  multi-audio HLS support remain hardware regression requirements. Installed
  versions are unchanged; all source changes remain uncommitted.

## Maintenance Record: 2026-09-04

- The TV reported a lost desktop pairing without a user-initiated reinstall.
  Passive inspection found the pairing form open, all webOS `localStorage`
  keys absent, and an IndexedDB audit remaining pending. The installed desktop
  server was healthy and still retained the earlier paired-device records.
- The retained `com.devyorg.anotheriptvplayer_1.7.16_all.ipk` package was
  installed in place on the configured LG OLED55B8PLA, then explicitly
  launched for pairing at the user's request. No content was selected or
  played.
- Pairing to the installed desktop server succeeded. The TV persisted the new
  connection record and other local settings, synchronized `Playlist-1`, and
  rendered a populated dashboard with five shelves.
- The initial in-place reinstall did not rebuild the package or run playback
  checks.
- A follow-up banner diagnosis found 76 of 77 dashboard images indefinitely
  waiting behind a pending IndexedDB image-cache read. webOS `1.7.17` adds a
  bounded cache-read timeout and a session circuit breaker so artwork falls
  back to its original URL instead of remaining blocked by storage.
- Version `1.7.17` also stores a small redundant pairing record in IndexedDB
  and restores the primary `localStorage` record at startup. Physical fault
  injection removed only the primary record; after an app restart the TV
  restored it, skipped pairing, and returned to the populated five-shelf
  dashboard.
- Fresh artwork still did not decode during the physical check because the
  external plain-HTTP image origin timed out from both the TV and desktop;
  HTTPS to the same origin also timed out. One previously cached blob rendered.
- Automated checks for `1.7.17`: 262 tests passed with one skipped;
  TypeScript and both modern and Chromium-53 legacy production builds passed.
  No playback checks were run. The retained `1.7.16` IPK is the rollback.

## Release Record: 2026-08-15

- webOS package `com.devyorg.anotheriptvplayer_1.7.16_all.ipk` was installed
  and launched on the configured physical TV.
- The exact reported title, `EN - Diary Of A Wimpy Kid 4K (2021)` (item
  `939307`), resumed from the desktop-managed `36.433` second checkpoint
  through HLS remux. The LG video element reached `readyState=4`, was not
  paused, reported no media error, and advanced normally. The remux retained
  native HEVC Main 10 `3840x2160` video and AAC-LC 5.1 audio.
- The provider permits one connection at a time. FFmpeg probes this Matroska
  file with overlapping HTTP Range requests, so a desktop-only input ticket
  now parks superseded local requests while closing and serializing provider
  requests. Provider keep-alive is disabled for this ticket. Do not enable
  FFmpeg `multiple_requests`: on this file it soft-seeks by draining about
  2.42 GB instead of requesting the Matroska index range.
- Managed VOD now retains the source container suffix, permits longer remux /
  transcode startup, limits emergency transcode to 1080p H.264 level 4.2, and
  advances proxy -> remux -> transcode when a VOD media clock remains at zero
  for 20 seconds despite a false native `playing` state.
- Forward and backward seeking were physically verified on the exact 4K MKV.
  Three Left presses moved the displayed absolute clock from `1:50` to `1:34`
  (native HLS time `73.096` to `57.861`) and playback continued at
  `readyState=4` without a media error.
- Movie resume was physically verified from the detail-screen label through
  actual native playback. This TV origin returned IndexedDB
  `QuotaExceededError`, so the TV now reads/writes desktop-managed history as
  a fallback when local persistence is unavailable.
- Movie detail now renders a desktop-authoritative Watch History card with the
  saved and total times, progress, app-locale timestamp, and remaining time.
  On the exact 4K title it physically rendered `11:48 / 56:11` and `44:22`
  remaining alongside separate Resume and Play From Start buttons.
- Automated checks: 260 webOS tests passed with one skipped; TypeScript and
  the Vite production build passed. The final focused Flutter playback/server
  run passed all 9 tests and focused static analysis reported no issues.
- Rollback artifact retained:
  `apps/webos/com.devyorg.anotheriptvplayer_1.7.13_all.ipk`.

## Release Record: 2026-08-11

- Source commit: `706a5523577c0fe6755255d6e93cd24a5f8b096b`, plus the recorded uncommitted workspace changes.
- Windows installer `Another-IPTV-Player-Setup-1.7.1.exe` was installed; the
  desktop LAN server was reachable from the TV.
- webOS package `com.devyorg.anotheriptvplayer_1.7.10_all.ipk` was installed
  and launched on the configured `tv` device.
- webOS package `com.devyorg.anotheriptvplayer_1.7.13_all.ipk` restores the
  last browsed dashboard/category/movie/series screen at launch (never player
  playback); a movie-detail restart was physically verified.
- Physical checks passed for desktop sync, Yellow channel list, numeric then
  programme up/down zapping, category grid ratings, and scoped category search.
- Watch-history resume remains physically reproduced as failing: native media
  time advances but no new local/server history row is written.
- Automated checks: webOS 238 tests passed with one skipped; TypeScript and
  Vite production builds passed.
- Rollback artifact retained:
  `apps/webos/com.devyorg.anotheriptvplayer_1.7.6_all.ipk`.

## Running State at Last Update

- The desktop source-tree release executable owned TCP `32145` during the
  physical-TV regression and remained running after the final test. At the
  last observation its PID was `89236`; treat that PID as volatile and verify
  the listener before relying on it.
- The installed desktop executable is
  `C:\Program Files\Another IPTV Player\iptv_player.exe` (`1.7.1+32`).
- The TV was reachable as an LG OLED55B8PLA running webOS 4.4; webOS `1.7.17`
  was installed. The final observation left the app on the synchronized Live
  TV dashboard after the pairing-recovery fault-injection check; no playback
  was started.

Runtime state does not survive a reboot or later user action. Confirm it with
the diagnostics guide.

## Source Versus Installed Desktop

The source and installed `1.7.1+32` desktop release contain the EPG
compatibility and LAN category-order/search changes. The installed `Program
Files` executable remained reachable from the TV during physical testing.

## Recent Commits

| Commit | Purpose |
| --- | --- |
| `706a552` | Provider-compatible EPG fallback and inferred now-playing flag |
| `66a89bc` | Sync stabilization and visible artwork preloading |
| `7478b8d` | Recover storage quota before pairing |
| `5e6693c` | Recover image-cache quota |
| `c30a334` | Refresh main shelves after category item sorting |
| `3141991` | Desktop release bump to 1.7.0 |
| `147ab64` | Persist category item sorting |
| `0d4ad3e` | Initial LG webOS client |
| `bea5031` | Desktop LAN server and IPTV features |

## Implemented Behavior

- Desktop-managed Xtream and M3U playlists with credentials kept off the TV.
- Lightweight TV synchronization instead of copying the complete catalogue.
- Desktop-owned category order, hidden categories, radio visibility,
  favorites, history, and shortcut pages.
- Category-aware TV search and category-order synchronization.
- Native LG playback with proxy, remux, and transcode fallback.
- Serialized desktop-only FFmpeg Range access for providers that allow only
  one connection, including random-access Matroska resume without exposing
  provider URLs to the TV.
- Managed VOD startup watchdog based on actual clock advancement, including
  recovery from Chromium 53's false `playing` state at `readyState=0`.
- Desktop-history fallback for resume when the TV origin's IndexedDB is
  effectively read-only.
- Desktop-authoritative Watch History on movie details with saved progress,
  watched time, remaining time, and distinct Resume / Play From Start actions.
- Dedicated programme up/down key handling; D-pad navigation remains focused
  on controls.
- Numeric shortcuts `0` through `9`; Yellow opens live channels and Blue cycles
  shortcut pages because LG reserves the More Actions key.
- TV storage quota recovery and bounded artwork preloading.
- EPG fallback to Xtream `get_simple_data_table` when `get_short_epg` is empty.

## Installed on TV; Physical Verification Pending

- A second quota cleanup migration and bounded image-cache writes address the
  reported repeated desktop-sync storage failure outside the now-verified
  watch-history fallback.
- Yellow opens live channels; Blue retains shortcut-page cycling.
- Category order refreshes from the desktop index, category grids have scoped
  search, and movie/series tiles show star ratings.
- Numeric shortcuts retain a programme-key queue containing current live,
  favorite, and shortcut channels.

These remaining changes have automated coverage and the TV-side changes are
installed in webOS `1.7.16`. Desktop-side LAN changes were exercised from the
source-tree release build; they are not yet installed into `Program Files`.

## Uncommitted Workspace Warning

The release artifacts were built from a dirty worktree at source commit
`706a552`. The worktree includes the feature changes, release-version changes,
documentation updates, pre-existing user changes, and OneDrive conflict-copy
files ending in `-test1-PC`. Preserve them; do not reset or overwrite them
during unrelated work.

## Next Safe Actions

1. Let the user confirm that the AAC-LC 5.1 track is audible through the TV's
   current audio/output setup; stream inspection proves the track is present
   but cannot prove room audio remotely.
2. Package/install the current desktop build only after explicit approval; the
   physical regression used the source-tree release executable.
3. Recheck synchronization and EPG through the installed server after that update.
4. Change the misleading aspect-ratio control: LG native playback ignores the
   current CSS implementation.
