# Another IPTV Player - Project Resume Index

Last updated: 2026-08-11

This is the main resume document for the customized Windows and LG webOS work.
Read it before changing, building, launching, installing, or diagnosing either
application.

The repository also has an extensionless `README` inherited from the upstream
project. It remains the public product overview; this file is the canonical
Markdown entry point for the customized engineering work.

## Resume Reading Order

1. [Current state](shared/docs/webos/current-state.md) - versions, running
   binaries, recent commits, and the next safe actions.
2. [Known issues](shared/docs/webos/known-issues.md) - confirmed defects,
   limitations, workarounds, and regression items.
3. [Architecture](shared/docs/webos/architecture.md) - desktop/TV ownership,
   synchronization, storage, and playback flow.
4. [Development and deployment](shared/docs/webos/development-and-deployment.md)
   - build, package, install, and versioning procedures.
5. [Testing and diagnostics](shared/docs/webos/testing-and-diagnostics.md) -
   automated checks, physical-TV safety, and connection troubleshooting.
6. [Client/server protocol](shared/docs/webos-client-server-protocol.md) - LAN
   API contract and security boundary.
7. [Feature parity](shared/docs/webos-feature-parity.md) - desktop/webOS
   capability matrix and validation status.

The webOS documentation has its own index at
[shared/docs/webos/README.md](shared/docs/webos/README.md).

## Standing Instructions

- Identify the target content before every playback test. Any content may be
  used only when the user has explicitly confirmed that the TV is free for
  testing; keep the volume low and do not rely on the last-played item.
- Do not launch the TV app, start playback, resume the last channel, or change
  channels unless the user has agreed and the target content is identified.
- Non-playback inspection of an already open dashboard is allowed when it does
  not navigate, select, or start content.
- The Windows app is the source of truth for playlists, credentials,
  categories, category order, hidden categories, radio visibility, favorites,
  history, shortcuts, and shared playback preferences.
- Never put provider credentials, pairing codes, developer passphrases, bearer
  tokens, or signed media URLs in documentation, commits, or command output.
- Do not build or replace the Windows installer unless the user explicitly
  asks for an installer. Local test builds are allowed.
- Do not deploy or launch a new TV package while the TV is in use unless the
  user explicitly asks.
- Preserve app data, playlists, favorites, history, and settings.
- The worktree may contain unrelated or externally generated changes. Never
  revert them. Stage only files that belong to the current task.

## Critical Runtime Warning

Do not replace the running installed desktop app with the executable under
`apps/flutter/build` during a live TV session without first verifying inbound
Windows Firewall access for that exact executable path.

This failure has happened physically: localhost requests worked, but the TV's
`/playlists` and `/shelves` requests remained pending and the dashboard showed
`Loading...`. Restoring the installed executable under `C:\Program Files`
immediately restored the catalogue.

See [Development and deployment](shared/docs/webos/development-and-deployment.md)
for the safe update procedure.

## Project Locations

- Windows desktop and LAN server: `apps/flutter`
- LG webOS client: `apps/webos`
- Shared engineering docs: `shared/docs`
- WebOS resume docs: `shared/docs/webos`
- Desktop/webOS API contract: `shared/docs/webos-client-server-protocol.md`
- Desktop/webOS parity matrix: `shared/docs/webos-feature-parity.md`

## Current Versions

- Flutter desktop source and installer artifact: `1.7.4+35`
- Installed desktop app: `1.7.1+32`
- webOS source/package: `1.7.16`; installed TV package: `1.7.13`
- webOS app ID: `com.devyorg.anotheriptvplayer`
- Desktop LAN port: `32145`; discovery UDP port: `32146`

Versions and runtime state can change. Confirm them against source and running
processes before deployment.

## Common Commands

From the repository root, prepare Flutter with:

```powershell
$env:GIT_CONFIG_GLOBAL='E:\Onedrive\OneDrive - Yorg\OneDrive\Code\IPTV\.codex-gitconfig'
$env:PATH='E:\Onedrive\OneDrive - Yorg\OneDrive\Code\IPTV\flutter-sdk\bin;' + $env:PATH
```

Desktop checks:

```powershell
cd apps\flutter
flutter test --no-pub
flutter analyze --no-pub
flutter build windows --release --no-pub
```

webOS checks:

```powershell
cd apps\webos
pnpm run test
pnpm run build
pnpm run package
```

`pnpm run tv:smoke` installs and launches the TV app. Do not use it merely to
verify installation; use the non-launching commands in the deployment guide.

## Important Source Files

- Desktop entry: `apps/flutter/lib/main.dart`
- Xtream repository and EPG: `apps/flutter/lib/repositories/iptv_repository.dart`
- LAN controller: `apps/flutter/lib/services/lan_server/lan_server_controller.dart`
- LAN library: `apps/flutter/lib/services/lan_server/lan_library_service.dart`
- FFmpeg pipeline: `apps/flutter/lib/services/lan_server/lan_media_pipeline.dart`
- webOS entry/UI: `apps/webos/src`
- webOS dashboard: `apps/webos/src/ui/screens/DashboardScreen.tsx`
- webOS player: `apps/webos/src/ui/screens/PlayerScreen.tsx`
- LG video adapter: `apps/webos/src/player/WebOSVideoAdapter.ts`
- webOS server client: `apps/webos/src/api/serverClient.ts`
- TV diagnostic script: `apps/webos/scripts/tv-diagnose.mjs`

## Git Baseline

The active development branch at this update is
`codex/webos-client-server`. The latest committed change is `706a552`, which
adds the provider-compatible EPG fallback. Check `git status` before every edit
because OneDrive conflict copies and unrelated modified files have appeared in
this workspace.
