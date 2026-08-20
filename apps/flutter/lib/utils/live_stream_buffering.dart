/// mpv (media_kit) demuxer/cache properties applied when a live stream opens.
///
/// media_kit's default network cache is small, so high-bitrate live channels
/// on a slightly bumpy provider connection can drain the buffer faster than it
/// refills and stall ("running out of buffer"). Players like IPTV Smarters keep
/// a much larger read-ahead buffer, which rides over those hiccups. These
/// properties give mpv a comparable cushion for live playback.
///
/// Values are plain byte counts / seconds as strings, which is what the libmpv
/// property interface expects. They are only applied to live streams so that
/// video-on-demand seeking behaviour is left unchanged.
const Map<String, String> liveStreamBufferingMpvProperties = {
  // Enable the demuxer cache for network playback.
  'cache': 'yes',
  // Keep up to ~30s of decoded-ahead media in the cache.
  'cache-secs': '30',
  // Forward read-ahead buffer: 150 MiB is plenty for HD/FHD live TS streams.
  'demuxer-max-bytes': '157286400',
  // Keep 50 MiB behind the play head so brief backward jitter does not re-fetch.
  'demuxer-max-back-bytes': '52428800',
  // Try to stay ~20s ahead of the play head.
  'demuxer-readahead-secs': '20',
  // Give a slow provider moment up to 60s before giving up the connection.
  'network-timeout': '60',
};

/// Default User-Agent used for live streams that do not carry their own.
///
/// Many Xtream providers give full throughput only to players they recognise
/// and throttle unknown clients (mpv's default UA gets throttled, which drains
/// the live buffer). VLC's User-Agent is broadly whitelisted, so live channels
/// stream at real-time speed like they do in dedicated IPTV players.
const String liveStreamDefaultUserAgent = 'VLC/3.0.20 LibVLC/3.0.20';
