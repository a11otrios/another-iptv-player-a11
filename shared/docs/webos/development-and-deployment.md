# webOS Development and Deployment

## Safety Before Commands

- Check whether the TV and desktop app are in use.
- Do not launch the TV app unless explicitly requested. Launch can resume prior
  playback.
- Identify the target content before any playback test. Any content may be
  used only after the user explicitly confirms that the TV is free for testing;
  keep the volume low and do not rely on the last-played item.
- Check `git status` and preserve unrelated changes and OneDrive conflict
  copies.
- Never echo credentials, pairing codes, passphrases, tokens, or signed URLs.

## Windows Desktop

Prepare the bundled Flutter SDK from the repository root:

```powershell
$env:GIT_CONFIG_GLOBAL='E:\Onedrive\OneDrive - Yorg\OneDrive\Code\IPTV\.codex-gitconfig'
$env:PATH='E:\Onedrive\OneDrive - Yorg\OneDrive\Code\IPTV\flutter-sdk\bin;' + $env:PATH
cd apps\flutter
```

Check and build:

```powershell
flutter test --no-pub
flutter analyze --no-pub
flutter build windows --release --no-pub
```

Only build the installer when the user explicitly requests it:

```powershell
.\windows\build_installer.ps1 -Version 1.7.4 -BuildNumber 35
```

The installer requests elevation because it writes to `Program Files`, writes
HKLM uninstall/application registry entries, and installs the Visual C++
runtime. The current NSIS script does not create a Windows Firewall rule.

### Firewall and Executable Paths

Windows Firewall permissions are path-specific. A local release executable can
listen on `0.0.0.0:32145` and work from `127.0.0.1` while LAN requests from the
TV remain pending.

For TV testing, prefer the properly installed executable:

```text
C:\Program Files\Another IPTV Player\iptv_player.exe
```

Do not switch a working TV session to
`apps/flutter/build/windows/x64/runner/Release/iptv_player.exe` unless inbound
access for that exact path has been verified. The safe release update is:

1. Confirm the TV is not playing content.
2. Stop the installed desktop app.
3. Run the installer with user approval.
4. Launch the installed app from `Program Files`.
5. Verify port `32145` and an actual TV connection.
6. Confirm the dashboard renders before testing playback.

## LG webOS Client

In Codex, load the workspace dependencies before assuming `node` or `pnpm` is
on `PATH`. The bundled runtime paths can vary between sessions.

From `apps/webos`:

```powershell
pnpm install
pnpm run test
pnpm run build
pnpm run package
```

The package output for version 1.7.16 is:

```text
apps/webos/com.devyorg.anotheriptvplayer_1.7.16_all.ipk
```

Version changes must update at least:

- `apps/webos/package.json`
- `apps/webos/package-lock.json`
- `apps/webos/public/appinfo.json`
- package/deploy script references and README output names

### Install Without Launching

After Developer Mode and Key Server are ready:

```powershell
pnpm exec ares-device --system-info --device tv
pnpm exec ares-install --device tv .\com.devyorg.anotheriptvplayer_1.7.16_all.ipk
pnpm exec ares-install --device tv --list
```

Do not use `pnpm run tv:smoke` unless launching is intended; that script checks,
installs, verifies, and launches the app.

### Developer Mode

- SSH user: `prisoner`
- CLI device name used in this workspace: `tv`
- Developer Mode and its key expire and may need renewal.
- Never record the developer passphrase in source or docs.

## Rollback

- Keep the last known working IPK until a new package passes dashboard and
  identified-target playback checks.
- A desktop rollback must preserve the database and shared-preference files.
- Do not delete webOS app data to solve a catalogue problem until connection,
  server, and cache-specific recovery paths have been checked.
- Reinstalling the webOS IPK may preserve app data; removing the app may not.

## Release Record

After any installation, update `current-state.md` with:

- source commit
- desktop and TV versions
- which executable/IPK is actually installed
- whether it was launched
- automated checks run
- physical-TV checks run
- rollback artifact
