# webOS Testing and Diagnostics

## Physical-TV Rules

- Identify the target before launch or playback; do not rely on the
  last-played item.
- Any content may be used for playback only after the user explicitly confirms
  the TV is free for testing. Keep the volume low.
- Do not launch, resume, switch, or seek content while the TV is being used.
- Prefer dashboard inspection and API checks before playback.
- Never print secrets from local storage, shared preferences, or provider URLs.

## Automated Checks

webOS:

```powershell
cd apps\webos
pnpm run test
pnpm run build
```

The build runs `tsc --noEmit` before Vite. Run focused tests while iterating and
the full suite before packaging.

Desktop LAN/EPG examples:

```powershell
cd apps\flutter
flutter test --no-pub test\services\lan_library_service_test.dart
flutter test --no-pub test\services\lan_server_integration_test.dart
flutter test --no-pub test\repositories\iptv_repository_epg_test.dart
```

## Confirm the Desktop Server

Check the executable and listener:

```powershell
Get-Process -Name iptv_player -ErrorAction SilentlyContinue |
  Select-Object Id,Path,StartTime
netstat -ano | Select-String ':32145|:32146'
```

Useful interpretation:

- `0.0.0.0:32145 LISTENING` proves the server bound a socket.
- A localhost request proves only local access.
- A connection such as `192.168.1.181:32145` to `192.168.1.168:*` proves the
  TV reached the server.
- Pending TV requests with no response, while localhost works, strongly point
  to Windows Firewall or executable-path permission.

Confirm current addresses with `ipconfig`; do not assume saved DHCP addresses.

## Inspect the Open TV App

`apps/webos/scripts/tv-diagnose.mjs` attaches to the webOS Chromium debugger on
port `9998`. It can report the visible screen, focused element, player state,
poster image states, console errors, and API request timing.

In Codex, load the workspace dependencies first when `node` is not available
on `PATH`, then invoke the bundled Node executable directly.

Read-only dashboard inspection:

```powershell
cd apps\webos
node .\scripts\tv-diagnose.mjs `
  --host 192.168.1.168 `
  --wait 3000 `
  --summary-only `
  --screenshot tv-diagnostic.png
```

Do not pass `--reload`, `--keys`, `--enter`, or playback-error options unless
their effect is intended. Reloading while the player is open can disrupt or
resume media.

## Dashboard Stuck on Loading

1. Confirm the installed desktop process is running.
2. Confirm TCP `32145` is listening.
3. Inspect the TV network log for `/api/v1/playlists` and `/api/v1/shelves`.
4. If both remain pending, check executable path and Firewall access.
5. If they return errors, inspect the sanitized API status and desktop logs.
6. If they return 200 but no cards render, inspect console exceptions and
   IndexedDB/cache state.
7. Do not clear app data until the failing layer is known.

## Artwork Diagnostics

The TV diagnostic reports `.poster-image` states:

- `loaded`: image decoded and displayed.
- `waiting`: bounded preload has not started this card yet.
- `loading`: request is active.
- `error` or fallback: source failed or cache recovery was used.

The physical webOS 4.4 browser lacks dependable modern lazy-loading behavior.
The app therefore preloads a bounded visible region and avoids loading the
entire catalogue at once.

## Storage Quota Diagnostics

Pairing and sync must not persist full catalogues in `localStorage`. When a
quota error occurs:

1. Record which store and operation failed.
2. Preserve the server connection and paired token.
3. Clear only disposable catalogue/image caches.
4. Retry lightweight synchronization.
5. Confirm the dashboard and category paging separately.

Error messages should identify whether connection storage, IndexedDB catalogue,
or artwork caching exceeded quota.

## Playback Regression

With identified target content, verify:

1. Direct or proxy playback starts.
2. Controls appear and auto-hide.
3. D-pad navigates controls without changing channels.
4. Programme up/down changes live channels even while controls are visible.
5. Blue opens/cycles shortcut pages; numeric shortcuts use the active page.
6. Favorite state changes and survives a desktop sync.
7. Audio/subtitle panels open and close.
8. EPG appears when the provider supplies a current schedule.
9. Back releases the active media/FFmpeg session.

Aspect ratio is currently excluded from pass criteria because LG ignores the
CSS implementation. Track it as a known issue instead of reporting it passed.

## Recording Evidence

For each issue record:

- date and app versions
- desktop executable path
- TV model/webOS version
- exact screen and content type
- remote keys/actions
- expected and observed behavior
- whether controls were visible
- sanitized network/console evidence
- screenshot path
- regression test added or still needed
