import { HistoryKind } from "../data/records";

/**
 * One playable entry handed to the player screen. Series detail builds a full
 * episode queue of these (tvOS pattern); live/vod pass a single-item queue or
 * a channel list for zapping.
 */
export interface PlayableItem {
  url: string;
  title: string;
  secondaryTitle?: string;
  imageURL?: string;
  isLive: boolean;
  /** Watch-history identity. */
  historyType: HistoryKind;
  historyStreamId: string;
  seriesId?: string | number;
  /** Opaque identity resolved by the paired desktop immediately before play. */
  serverItemId?: string;
  serverEpisodeId?: string;
  seasonNumber?: number;
  containerExtension?: string;
  resumeTimeMs?: number;
  /** Catalog runtime fallback for LG builds that report a zero duration. */
  durationMs?: number;
  /** Per-channel override from M3U (#EXTVLCOPT etc.). */
  userAgent?: string;
}

/** Converts provider runtime metadata to a trustworthy positive duration. */
export function mediaDurationMs(
  duration: string | undefined,
  durationSecs: number | undefined,
): number | undefined {
  const parts = duration?.trim().split(":").map(Number);
  if (
    parts &&
    (parts.length === 2 || parts.length === 3) &&
    parts.every((part) => isFinite(part) && part >= 0) &&
    parts[parts.length - 1] < 60 &&
    parts[parts.length - 2] < 60
  ) {
    const seconds = parts.length === 3
      ? parts[0] * 3600 + parts[1] * 60 + parts[2]
      : parts[0] * 60 + parts[1];
    if (seconds > 0) return Math.floor(seconds * 1000);
  }
  const seconds = Number(durationSecs);
  return isFinite(seconds) && seconds > 0
    ? Math.floor(seconds * 1000)
    : undefined;
}
