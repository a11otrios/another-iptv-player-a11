# webOS Client/Server Feature Parity

This matrix compares the paired LG client with the current Flutter desktop
player. `lennylxx/webos-iptv-player` is a secondary reference for LG playback
and remote-control behavior; it does not replace the desktop-owned data model.

## Library and state

| Capability | Ownership | Current evidence |
| --- | --- | --- |
| Multiple Xtream and M3U playlists | Desktop | `/playlists`, lightweight server sync, IndexedDB navigation index |
| Live, movie, and series catalogs | Desktop | bounded shelves, server-paged categories, single-item/series/VOD endpoints |
| Provider credentials hidden from TV | Desktop | opaque identities and playback descriptors |
| Search and catalog sorting | Split | server catalog data; TV search and A-Z/Z-A/date/rating modes |
| Hidden categories and adult filtering | Desktop/TV | server-side category, shelf, item, and search enforcement |
| Favorites | Desktop authoritative | authenticated writes and TV cache |
| Watch history and resume | Desktop authoritative | periodic writes, resume descriptors, TV cache |
| Channel shortcuts | Desktop | pages A/S/D/F/G exposed to numeric TV keys; Blue opens the channel panel and cycles the active page |
| Temporary offline startup | TV | paired connection, playlist/category index, preferences, favorites, and history remain cached; item browsing requires the desktop |
| DHCP address recovery | TV | discovery validates the existing token and retries at the new address |
| Runtime language switching | TV | all ten desktop languages, including pairing and compatibility flows |

## Playback

| Capability | Current evidence |
| --- | --- |
| LG native media pipeline | `WebOSVideoAdapter` with capability-gated MIME hints and native probing fallback |
| Browser preview fallback | `Html5VideoAdapter` with development HLS.js path |
| Proxy and HLS manifest rewrite | signed desktop stream tickets |
| Media authorization | short-lived grants hide the paired bearer token and honor device revocation |
| Unsupported-container recovery | credential-safe proxy -> FFmpeg remux -> transcode |
| Silent LG pipeline recovery | stall watchdog and fresh video-element replacement |
| Suspend/resume | visibility lifecycle with position restoration |
| Live channel zapping | CH keys, overlay channel list, active-page numeric shortcuts |
| Movie/episode resume | synchronized history position |
| Episode auto-next | ordered queue and countdown |
| Audio and embedded subtitle tracks | LG `audioTracks`/`textTracks` adapter |
| Cross-device track preferences | TV audio/subtitle choices and explicit subtitle-off state persist on desktop |
| Online and cached subtitles | desktop OpenSubtitles search/download, expiring WebVTT URL; cached external WebVTT physically proven on LG |
| Subtitle timing offset | TV +/-0.5 second controls, desktop persistence |
| Subtitle appearance | desktop font, spacing, colors, weight, alignment, and padding synchronized to TV |
| Aspect ratio | per-stream fit/crop/stretch preference |
| Now/next EPG | server short EPG shown in player overlay |
| Player information | TV modal with type, format, opaque identity, and EPG |
| Movie trailers | webOS application manager opens the provider trailer URL |

## Validation status

Physical-TV validation on an LG OLED55B8PLA running webOS 4.4 covers pairing,
lightweight sync, Live/Movie/Series shelves, details, category totals,
automatic page-two loading, lazy series/episode retrieval, pause, seek,
duration/clock advancement, now/next EPG, favorites, history, track and aspect
panels, retry, and live channel navigation. Playback is proven through direct
MP4 and MPEG-TS proxying plus FFmpeg remux and transcode fallbacks. Compatibility
session replacement and terminal Retry both release the superseded FFmpeg
process and temporary media directory.

Shortcut pages `A`, `S`, `D`, `F`, and `G` were fetched from the desktop and
cycled with Blue on the TV. A temporary family-safe assignment proved that a
numeric press atomically switched the player to the matching desktop channel;
the original desktop shortcuts were restored afterward.

External WebVTT was validated end to end with Paddington: the TV fetched the
desktop cache descriptor and signed subtitle file, loaded an English cue, and
rendered it over advancing video. The temporary subtitle preference and file
were removed after the test. Suspend/resume is covered by an adapter test that
recreates the video element and restores a playing VOD position.

Remaining hardware-dependent coverage is provider-specific embedded-track
switching, HDR/audio passthrough, and a real application-background lifecycle.
Online OpenSubtitles search also requires desktop API credentials. Windows
release builds include the pinned FFmpeg binary and its license notices.
