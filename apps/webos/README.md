# Another IPTV Player for LG webOS

This is the TV client for the desktop-managed Another IPTV Player library. The
desktop owns provider credentials, imports, metadata, favorites, and history;
the TV stores a paired device token, a small navigation index, and synchronized
state. Dashboard shelves and category pages are fetched lazily so very large
provider catalogs are never mirrored into webOS IndexedDB.

## Develop

```powershell
pnpm install
pnpm run dev
pnpm run test
pnpm run build
```

The browser preview uses `hls.js` for HLS. The packaged webOS app uses LG's
native `<video>` pipeline with explicit MIME sources and fresh-element recovery.

For paired playlists, the TV also uses the desktop for signed media proxying,
optional FFmpeg remux/transcode fallback, EPG, favorites, history, and online
subtitle search. Configure OpenSubtitles credentials in the desktop app; they
are never copied to the TV. Windows release builds bundle the pinned FFmpeg
binary used for compatibility playback. Development builds look for it in this
order:

1. An explicit application override or `AIPTV_FFMPEG` environment variable.
2. `ffmpeg`/`ffmpeg.exe` beside the desktop executable.
3. `tools/ffmpeg/ffmpeg` beneath the executable or working directory.
4. The system `PATH`.

The desktop Settings card reports whether the resolved binary is usable.

## Player remote controls

- `P+` / `P-`: next or previous channel in the current live queue when the TV
  firmware exposes those keys to web apps. LG reserves them on some models.
- Circular D-pad Up/Down: navigate the player controls only; these do not
  change channels.
- Blue: open the live-channel panel. Press Blue again to cycle shortcut pages
  `A`, `S`, `D`, `F`, and `G`.
- `0`-`9`: play the desktop shortcut assigned on the active page.
- Yellow: audio and subtitle tracks, online subtitle search, and subtitle
  timing.
- Green: cycle the stream's saved aspect mode.
- Red: add or remove the current item from favorites.

The remote's `...` button is reserved by webOS for the system More Actions
menu and is not delivered to applications as a dependable key event.

## Install on an LG TV

1. Install LG's Developer Mode app on the TV, sign in, and enable Developer
   Mode. The TV reboots.
2. Add the TV with `pnpm exec ares-setup-device --add tv`. Use the TV's IP,
   port `9922`, and SSH user `prisoner`.
3. Open Developer Mode again, enable Key Server, then run
   `pnpm exec ares-novacom --device tv --getkey` and enter the six-character
   passphrase shown by the TV.
4. Run `pnpm run package` to produce `com.devyorg.anotheriptvplayer_1.7.2_all.ipk`.
5. Run `pnpm run tv:smoke -- --device tv`. This checks connectivity, installs
   the IPK, verifies the app ID, and launches it. Use a different device name if
   that is how the TV was configured.
6. Start the desktop app, open Settings, and enter its LAN server address and
   pairing code on the TV.

The Developer Mode session expires unless the TV app's session time is extended.
Re-enable Developer Mode and refresh the CLI key when an existing device stops
accepting connections.

See `NOTICE` for the lennylxx/webos-iptv-player attribution.
