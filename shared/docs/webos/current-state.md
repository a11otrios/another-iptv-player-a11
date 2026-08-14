# webOS Current State

Last updated: 2026-08-11

This file records facts needed to resume safely. Verify volatile network and
process details before relying on them.

## Versions and Devices

| Component | State |
| --- | --- |
| Flutter desktop source | `1.7.1+32` |
| Windows installer artifact | `1.7.1` |
| Installed Windows desktop | `1.7.1+32` |
| webOS source/installed package | `1.7.13` |
| webOS app ID | `com.devyorg.anotheriptvplayer` |
| Physical TV | LG OLED55B8PLA, webOS 4.4 / Chromium 53 |
| CLI device name | `tv` |
| Desktop LAN server | TCP `32145`, UDP discovery `32146` |

The observed TV address was `192.168.1.168` and the desktop address was
`192.168.1.181`. Both are DHCP addresses and must be rechecked.

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

- No `iptv_player` process or TCP/UDP `32145`/`32146` listener was observed
  immediately before the release build and TV deployment.
- The installed desktop executable is
  `C:\Program Files\Another IPTV Player\iptv_player.exe` (`1.7.1+32`).
- The TV was reachable as an LG OLED55B8PLA running webOS 4.4; webOS `1.7.10`
  was installed and returned to its normal dashboard after testing.

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
- Dedicated programme up/down key handling; D-pad navigation remains focused
  on controls.
- Numeric shortcuts `0` through `9`; Yellow opens live channels and Blue cycles
  shortcut pages because LG reserves the More Actions key.
- TV storage quota recovery and bounded artwork preloading.
- EPG fallback to Xtream `get_simple_data_table` when `get_short_epg` is empty.

## Installed on TV; Physical Verification Pending

- A second quota cleanup migration and bounded image-cache writes address the
  reported repeated desktop-sync storage failure.
- Resume labels refresh after playback and use the latest persisted position.
- Yellow opens live channels; Blue retains shortcut-page cycling.
- Category order refreshes from the desktop index, category grids have scoped
  search, and movie/series tiles show star ratings.
- Numeric shortcuts retain a programme-key queue containing current live,
  favorite, and shortcut channels.

These changes have automated coverage and the TV-side changes are installed in
webOS `1.7.7`. The package was deliberately not launched, so all seven reported
behaviors still require physical-TV regression. Desktop-side LAN changes are in
the `1.7.1` installer artifact but are not yet in the installed desktop app.

## Uncommitted Workspace Warning

The release artifacts were built from a dirty worktree at source commit
`706a552`. The worktree includes the feature changes, release-version changes,
documentation updates, pre-existing user changes, and OneDrive conflict-copy
files ending in `-test1-PC`. Preserve them; do not reset or overwrite them
during unrelated work.

## Next Safe Actions

1. Run a focused physical-TV regression of the seven reported behaviors using
   known children's content for playback checks.
2. Install the `1.7.1` Windows build only after explicit approval to run the
   installer, then keep the installed desktop app running while the TV is in use.
3. Recheck synchronization and EPG through the installed server after that update.
4. Change the misleading aspect-ratio control: LG native playback ignores the
   current CSS implementation.
