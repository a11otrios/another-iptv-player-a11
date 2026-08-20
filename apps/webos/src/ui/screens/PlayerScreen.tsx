import {
  ReactNode,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  getCurrentFocusKey,
  setFocus,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import { FavoriteKind, PlaylistRecord } from "../../data/records";
import {
  getFavorites,
  isFavorite,
  toggleFavorite,
} from "../../data/favoritesRepo";
import {
  chooseResumePositionMs,
  getResumePositionMs,
  resolveHistoryPositionMs,
  saveProgress,
} from "../../data/watchHistoryRepo";
import { settings } from "../../data/settings";
import { createPlayer } from "../../player/playerFactory";
import { AspectMode, PlayerPort, PlayerState, TrackInfo } from "../../player/PlayerPort";
import {
  applyTrackPreferences,
  rememberSubtitlesOff,
  rememberTrackSelection,
} from "../../player/trackPreferences";
import { sanitizeSubtitleText } from "../../player/subtitleText";
import {
  hasPlaybackAdvanced,
  nextCompatibilityFallback,
  preferredInitialCompatibilityMode,
} from "../../player/compatibilityFallback";
import {
  IDLE_SEEK_STREAK,
  nextSeekStep,
  SeekStreak,
} from "../../player/seekAcceleration";
import { PlayableItem } from "../../models/playable";
import {
  CHANNEL_SHORTCUT_PAGES,
  ChannelShortcutPage,
  mergeChannelShortcutSources,
  nextChannelShortcutPage,
} from "../../models/channelShortcuts";
import { useNavigation } from "../../navigation/NavigationStack";
import { registerBackInterceptor } from "../../navigation/backHandler";
import {
  channelStepForKeyCode,
  KEY,
  normalizeKeyCode,
  playerPanelForColorKey,
} from "../../navigation/keys";
import { t } from "../../i18n";
import {
  ServerClient,
  ServerSubtitleDescriptor,
  ServerSubtitleIdentity,
} from "../../api/serverClient";
import { Modal } from "../components/Modal";
import { TrackSettingsPanel } from "../player/TrackSettingsPanel";
import { OnlineSubtitlePanel } from "../player/OnlineSubtitlePanel";
import { LiveChannelPanel } from "../player/LiveChannelPanel";
import { getAspectMode, nextAspectMode, setAspectMode as saveAspectMode } from "../../player/aspectPreference";

// Full player (phase 4): queue prev/next (episode nav & live zapping), track
// settings with persisted language preference, app-drawn subtitles, next-
// episode auto-advance, watch-history recording.

const CONTROLS_HIDE_MS = 5000;
const HISTORY_TICK_MS = 5000;
const PLAYER_STARTUP_TIMEOUT_MS = 20_000;
const AUTO_ADVANCE_SECONDS = 10;
const SEEK_COMMIT_DELAY_MS = 450;

// Player focus model: the visible play/pause button (bottom center) is the
// focus home. ↑ from it reaches the seek bar (VOD only) — ←/→ scrub ONLY
// there. → reaches the bottom-right button row (favorite / channels /
// tracks). All arrows are routed explicitly and dead ends are consumed:
// Norigin's geometric adjacency is unreliable across the sparse overlay.
const PLAYER_PLAY_KEY = "player-play-button";
const PLAYER_SEEK_KEY = "player-seek-bar";
const PLAYER_TRACKS_KEY = "player-tracks-button";
const PLAYER_FAV_KEY = "player-fav-button";
const PLAYER_CHANNELS_KEY = "player-channels-button";
const PLAYER_ASPECT_KEY = "player-aspect-button";
const PLAYER_INFO_KEY = "player-info-button";
const PLAYER_RETRY_KEY = "player-retry-button";

function ChromeButton({
  focusKey,
  onPress,
  leftKey,
  rightKey,
  upKey,
  children,
}: {
  focusKey: string;
  onPress: () => void;
  leftKey?: string;
  rightKey?: string;
  upKey?: string;
  children: ReactNode;
}) {
  const { ref, focused } = useFocusable({
    focusKey,
    onEnterPress: onPress,
    onArrowPress: (direction: string): boolean => {
      const target =
        direction === "left"
          ? leftKey
          : direction === "right"
            ? rightKey
            : direction === "up"
              ? upKey
              : undefined;
      if (target) setFocus(target);
      return false;
    },
  });
  return (
    <div
      ref={ref}
      data-focused={focused ? "true" : "false"}
      data-player-control={focusKey}
      className={`player-chrome-button${focused ? " focused" : ""}`}
      onClick={onPress}
    >
      {children}
    </div>
  );
}

function PlayPauseButton({
  paused,
  buffering,
  onToggle,
  upKey,
  rightKey,
}: {
  paused: boolean;
  buffering: boolean;
  onToggle: () => void;
  upKey?: string;
  rightKey?: string;
}) {
  const { ref, focused } = useFocusable({
    focusKey: PLAYER_PLAY_KEY,
    onEnterPress: onToggle,
    onArrowPress: (direction: string): boolean => {
      if (direction === "up" && upKey) setFocus(upKey);
      else if (direction === "right" && rightKey) setFocus(rightKey);
      return false;
    },
  });
  return (
    <div
      ref={ref}
      className={`player-play-button${focused ? " focused" : ""}`}
    >
      {buffering ? <span className="play-spinner" /> : paused ? "▶" : "❚❚"}
    </div>
  );
}

function SeekBar({
  positionMs,
  durationMs,
  onStep,
  onToggle,
}: {
  positionMs: number;
  durationMs: number;
  onStep: (dir: -1 | 1) => void;
  onToggle: () => void;
}) {
  const { ref, focused } = useFocusable({
    focusKey: PLAYER_SEEK_KEY,
    onEnterPress: onToggle,
    // Scrubbing lives HERE and only here: ←/→ accumulate a seek while focus
    // stays put; ↓ returns to play/pause; ↑ is a dead end (consumed).
    onArrowPress: (direction: string): boolean => {
      if (direction === "left") onStep(-1);
      else if (direction === "right") onStep(1);
      else if (direction === "down") setFocus(PLAYER_PLAY_KEY);
      return false;
    },
  });
  const ratio =
    durationMs > 0 ? Math.min(Math.max(positionMs / durationMs, 0), 1) : 0;
  return (
    <div ref={ref} className={`player-seek${focused ? " focused" : ""}`}>
      <span className="player-time">{fmt(positionMs)}</span>
      <div className="seek-track">
        <div className="seek-fill" style={{ width: `${ratio * 100}%` }} />
        <div className="seek-thumb" style={{ left: `${ratio * 100}%` }} />
      </div>
      <span className="player-time">
        {durationMs > 0 ? fmt(durationMs) : "–"}
      </span>
    </div>
  );
}

/**
 * What the red key / heart button favorites for the current item: the live
 * channel (Xtream or M3U), the movie, or — from an episode — the series.
 */
function favoriteKeyFor(
  playlist: PlaylistRecord,
  item: PlayableItem,
): { kind: FavoriteKind; itemId: string } | null {
  if (item.historyType === "series") {
    return item.seriesId !== undefined
      ? { kind: "series", itemId: String(item.seriesId) }
      : null;
  }
  if (item.historyType === "vod") {
    return { kind: "vod", itemId: item.historyStreamId };
  }
  return {
    kind: playlist.type === "m3u" ? "m3u" : "live",
    itemId: item.historyStreamId,
  };
}

function fmt(ms: number): string {
  const total = Math.max(Math.floor(ms / 1000), 0);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => (n < 10 ? `0${n}` : String(n));
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

function RetryButton({ onRetry }: { onRetry: () => void }) {
  const { ref, focused } = useFocusable({
    focusKey: PLAYER_RETRY_KEY,
    onEnterPress: onRetry,
  });
  return (
    <div
      ref={ref}
      className={`player-retry-button${focused ? " focused" : ""}`}
    >
      <span className="player-retry-icon">&#8635;</span>
      <span>{t("download.retry")}</span>
    </div>
  );
}

function PlayerInfoPanel({ item, epgLine }: { item: PlayableItem; epgLine: string | null }) {
  const rows = [
    [t("player.info.name"), item.title],
    [t("player.info.type"), item.historyType === "live" ? t("stream.live") : item.historyType === "vod" ? t("tabs.movies") : t("tabs.series")],
    [t("player.info.format"), item.containerExtension?.toUpperCase()],
    [t("player.info.id"), item.serverEpisodeId ?? item.serverItemId ?? item.historyStreamId],
    ["EPG", epgLine],
  ].filter((row): row is [string, string] => !!row[1]);
  return (
    <div className="player-info-panel">
      <h2>{t("player.info.title")}</h2>
      {rows.map(([label, value]) => (
        <div key={label} className="player-info-row">
          <span>{label}</span>
          <strong>{value}</strong>
        </div>
      ))}
    </div>
  );
}

function subtitleIdentity(
  playlist: PlaylistRecord,
  item: PlayableItem,
): ServerSubtitleIdentity {
  return {
    playlistId: playlist.id,
    type: item.historyType,
    itemId: item.serverItemId ?? item.historyStreamId,
    episodeId: item.serverEpisodeId,
    title: item.title,
    season: item.seasonNumber,
  };
}

export function PlayerScreen({
  playlist,
  items: initialItems,
  startIndex,
}: {
  playlist: PlaylistRecord;
  items: PlayableItem[];
  startIndex: number;
}) {
  const { pop } = useNavigation();
  const containerRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<PlayerPort | null>(null);
  const [items, setItems] = useState(initialItems);
  const itemsRef = useRef(initialItems);
  itemsRef.current = items;
  const [index, setIndex] = useState(startIndex);
  const indexRef = useRef(startIndex);
  const item = items[index];

  const [state, setState] = useState<PlayerState>("idle");
  const [positionMs, setPositionMs] = useState(0);
  const [durationMs, setDurationMs] = useState(0);
  const [buffering, setBuffering] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [subtitleText, setSubtitleText] = useState("");
  const [textDisabled, setTextDisabled] = useState(false);
  const textDisabledRef = useRef(false);
  const [tracks, setTracks] = useState<TrackInfo[]>([]);
  const [selectedTracks, setSelectedTracks] = useState<{
    AUDIO?: number;
    TEXT?: number;
    VIDEO?: number;
  }>({});
  const [panel, setPanel] = useState<"none" | "tracks" | "channels" | "subtitleSearch" | "info">("none");
  const [externalSubtitleLoaded, setExternalSubtitleLoaded] = useState(false);
  const [subtitleOffsetMs, setSubtitleOffsetMs] = useState(0);
  const [countdown, setCountdown] = useState<number | null>(null);
  const [aspectMode, setAspectModeState] = useState<AspectMode>("contain");
  const [epgLine, setEpgLine] = useState<string | null>(null);
  const countdownTimer = useRef<number | undefined>(undefined);
  // Ref mirrors so the global keydown/back handlers can read panel/countdown
  // without listing them as effect deps — re-registering window listeners
  // once per countdown second / panel toggle is avoidable churn.
  const panelRef = useRef(panel);
  panelRef.current = panel;
  const countdownRef = useRef(countdown);
  countdownRef.current = countdown;

  const [controlsVisible, setControlsVisible] = useState(true);
  const controlsRef = useRef(true);
  const hideTimer = useRef<number | undefined>(undefined);

  // Rapid ←/→ presses accumulate into one seek committed after a short pause;
  // issuing an AVPlay seek per keypress queues slow pipeline flushes (laggy).
  // Sustained same-direction presses accelerate the step (seekAcceleration).
  const pendingSeekRef = useRef<number | null>(null);
  const seekCommitTimer = useRef<number | undefined>(undefined);
  const seekStreakRef = useRef<SeekStreak>(IDLE_SEEK_STREAK);
  const lastShownSecond = useRef(-1);
  const prefsAppliedRef = useRef(false);
  const compatibilityStageRef = useRef(0);
  const startupTimerRef = useRef<number | undefined>(undefined);
  const startupBaselineRef = useRef(0);
  const playbackTimelineOffsetRef = useRef(0);
  const requestedStartPositionRef = useRef<number | undefined>(undefined);
  const shortcutsRef = useRef<Record<string, { itemId: string; name: string; imageUrl?: string }>>({});
  const [shortcutPage, setShortcutPage] = useState<ChannelShortcutPage>("A");
  const shortcutPageRef = useRef<ChannelShortcutPage>("A");
  const shortcutRequestRef = useRef(0);
  const activeServerPlaybackUrlRef = useRef<string | null>(null);
  const historyWriteRef = useRef<Promise<void>>(Promise.resolve());
  const historyCheckpointRef = useRef({ key: "", positionMs: 0 });
  const latestPlaybackRef = useRef({ positionMs: 0, durationMs: 0 });
  const hasReliablePositionRef = useRef(false);

  const stepSeek = useCallback((dir: -1 | 1) => {
    const player = playerRef.current;
    if (!player) return;
    const step = nextSeekStep(seekStreakRef.current, dir, Date.now());
    seekStreakRef.current = step.streak;
    const current = itemsRef.current[indexRef.current];
    const duration =
      player.getDurationMs() ||
      latestPlaybackRef.current.durationMs ||
      current?.durationMs ||
      0;
    const timelineOffset = playbackTimelineOffsetRef.current;
    const base =
      pendingSeekRef.current ?? player.getPositionMs() + timelineOffset;
    let target = Math.max(base + step.deltaMs, 0);
    if (duration > 0) target = Math.min(target, duration - 1000);
    pendingSeekRef.current = target;
    latestPlaybackRef.current.positionMs = target;
    hasReliablePositionRef.current = true;
    setPositionMs(target); // optimistic timeline feedback
    window.clearTimeout(seekCommitTimer.current);
    seekCommitTimer.current = window.setTimeout(() => {
      const commit = pendingSeekRef.current;
      pendingSeekRef.current = null;
      if (commit !== null) {
        void player.seekTo(Math.max(commit - playbackTimelineOffsetRef.current, 0));
      }
    }, SEEK_COMMIT_DELAY_MS);
  }, []);

  const hideControls = useCallback(() => {
    setControlsVisible(false);
    controlsRef.current = false;
  }, []);

  const showControls = useCallback(() => {
    // Clock ticks are suppressed while the OSD is hidden (nothing consumes
    // them) — re-sync on reveal so the seek bar never flashes a stale time.
    const player = playerRef.current;
    if (player && pendingSeekRef.current === null) {
      const p = player.getPositionMs() + playbackTimelineOffsetRef.current;
      lastShownSecond.current = Math.floor(p / 1000);
      setPositionMs(p);
    }
    setControlsVisible(true);
    controlsRef.current = true;
    window.clearTimeout(hideTimer.current);
    hideTimer.current = window.setTimeout(hideControls, CONTROLS_HIDE_MS);
  }, [hideControls]);

  const togglePlay = useCallback(() => {
    const player = playerRef.current;
    if (!player) return;
    player.getState() === "playing" ? player.pause() : player.play();
  }, []);

  // Focus home when the overlay (re)appears: play/pause by default, or the
  // seek bar when the reveal came from a seek-intent key (←/→ while hidden).
  const revealFocusRef = useRef<string | null>(null);
  const horizontalFocusIndexRef = useRef(0);
  useEffect(() => {
    if (!controlsVisible) return;
    const target = revealFocusRef.current ?? PLAYER_PLAY_KEY;
    revealFocusRef.current = null;
    if (target === PLAYER_PLAY_KEY) horizontalFocusIndexRef.current = 0;
    setFocus(target);
  }, [controlsVisible]);

  useEffect(() => {
    if (!error) return;
    requestAnimationFrame(() => setFocus(PLAYER_RETRY_KEY));
  }, [error]);

  // Favorite state for the current item (series episodes favorite the series).
  const favKey = useMemo(() => favoriteKeyFor(playlist, item), [playlist, item]);
  const [favorite, setFavorite] = useState(false);
  const favoriteRef = useRef(false);
  const favoriteWritePendingRef = useRef(false);
  const favoriteRequestRef = useRef(0);
  useEffect(() => {
    const requestId = ++favoriteRequestRef.current;
    favoriteRef.current = false;
    setFavorite(false);
    if (!favKey) return;
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const state = await isFavorite(db, playlist.id, favKey.kind, favKey.itemId);
      if (!cancelled && requestId === favoriteRequestRef.current) {
        favoriteRef.current = state;
        setFavorite(state);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist.id, favKey]);

  const toggleFav = useCallback(() => {
    if (!favKey || favoriteWritePendingRef.current) return;
    favoriteWritePendingRef.current = true;
    const requestId = ++favoriteRequestRef.current;
    const previous = favoriteRef.current;
    favoriteRef.current = !previous;
    setFavorite(!previous);
    void (async () => {
      try {
        const db = await getDb();
        const saved = await toggleFavorite(
          db,
          playlist.id,
          favKey.kind,
          favKey.itemId,
          item.title,
          item.imageURL,
        );
        if (requestId === favoriteRequestRef.current) {
          favoriteRef.current = saved;
          setFavorite(saved);
        }
      } catch {
        if (requestId === favoriteRequestRef.current) {
          favoriteRef.current = previous;
          setFavorite(previous);
        }
      } finally {
        favoriteWritePendingRef.current = false;
      }
    })();
  }, [playlist.id, favKey, item.title, item.imageURL]);

  const closePanel = useCallback(() => {
    setPanel("none");
    horizontalFocusIndexRef.current = 0;
    setFocus(PLAYER_PLAY_KEY);
  }, []);

  const loadShortcutPage = useCallback(async (page: ChannelShortcutPage) => {
    if (!playlist.managedByServer) return;
    shortcutPageRef.current = page;
    setShortcutPage(page);
    shortcutsRef.current = {};
    const requestId = ++shortcutRequestRef.current;
    try {
      const shortcuts = await ServerClient.connected()?.shortcuts(playlist.id, page);
      if (requestId === shortcutRequestRef.current && shortcuts) {
        shortcutsRef.current = shortcuts;
      }
    } catch {}
  }, [playlist.id, playlist.managedByServer]);

  const cycleShortcutPage = useCallback(() => {
    void loadShortcutPage(nextChannelShortcutPage(shortcutPageRef.current));
  }, [loadShortcutPage]);

  useEffect(() => {
    void loadShortcutPage("A");
  }, [loadShortcutPage]);

  // Stable identity: LiveChannelPanel is memoized, an inline closure would
  // re-render every mounted channel row whenever the player re-renders.
  const zapFromPanel = useCallback(
    (target: number) => {
      closePanel();
      void openIndexRef.current(target);
    },
    [closePanel],
  );

  const flushHistory = useCallback((): Promise<void> => {
    const player = playerRef.current;
    const current = itemsRef.current[indexRef.current];
    if (!player || !current) return Promise.resolve();
    const lastTimeMs = resolveHistoryPositionMs(
      player.getPositionMs() + playbackTimelineOffsetRef.current,
      latestPlaybackRef.current.positionMs,
      hasReliablePositionRef.current,
    );
    if (!current.isLive && lastTimeMs < 5000) return Promise.resolve();
    // Snapshot before queueing: later channel switches replace itemsRef and
    // reset the player timeline, but this write still belongs to the item that
    // was current when flushHistory was requested.
    const entry = {
        playlistId: playlist.id,
        type: current.historyType,
        streamId: current.historyStreamId,
        // Native webOS can briefly report zeroes while it processes a media
        // event. Retain the last trustworthy event values for history writes
        // so a valid checkpoint is not silently discarded by saveProgress.
        lastTimeMs,
        durationMs:
          player.getDurationMs() ||
          latestPlaybackRef.current.durationMs ||
          current.durationMs ||
          0,
        lastWatchedAt: Date.now(),
        title: current.title,
        secondaryTitle: current.secondaryTitle,
        imageURL: current.imageURL,
        seriesId: current.seriesId,
        containerExtension: current.containerExtension,
    };
    const write = async () => {
      try {
        await saveProgress(await getDb(), entry);
      } catch (error) {
        console.warn("[player] could not persist watch history", error);
      }
    };
    const pending = historyWriteRef.current.then(write, write);
    historyWriteRef.current = pending;
    return pending;
  }, [playlist.id]);

  const cancelCountdown = useCallback(() => {
    window.clearInterval(countdownTimer.current);
    setCountdown(null);
  }, []);

  const releaseActiveMediaSession = useCallback(async (expectedUrl?: string) => {
    const url = activeServerPlaybackUrlRef.current;
    if (!url || (expectedUrl && expectedUrl !== url)) return;
    activeServerPlaybackUrlRef.current = null;
    const server = ServerClient.connected();
    if (!server) return;
    try {
      await server.releasePlayback(url);
    } catch {}
  }, []);

  const openIndex = useCallback(
    async (
      nextIndex: number,
      resumeOverrideMs?: number,
      modePreference?: "remux" | "transcode",
      queueOverride?: PlayableItem[],
    ) => {
      const player = playerRef.current;
      const nextItems = queueOverride ?? itemsRef.current;
      const next = nextItems[nextIndex];
      if (!player || !next) return;
      const compatibilityMode =
        modePreference ??
        preferredInitialCompatibilityMode({
          managedByServer: playlist.managedByServer === true,
          isLive: next.isLive,
          containerExtension: next.containerExtension,
          userAgent: navigator.userAgent,
        }) ??
        undefined;
      window.clearTimeout(startupTimerRef.current);
      if (!modePreference) {
        compatibilityStageRef.current = compatibilityMode === "remux" ? 1 : 0;
      }
      cancelCountdown();
      // BEFORE the timeline resets below: showControls re-syncs positionMs
      // from the still-loaded OLD stream — called later it would overwrite
      // the fresh zeros and the seek bar would show the previous episode's
      // time until the new stream's first tick.
      showControls();
      await flushHistory();
      await releaseActiveMediaSession();
      if (compatibilityMode) {
        // Detach the failed direct/remux source before FFmpeg opens the same
        // provider URL. Some providers reject that overlapping second input
        // with a 5XX, leaving a ready fallback unable to reach the TV.
        player.stop();
        await new Promise<void>((resolve) => window.setTimeout(resolve, 750));
      }
      playbackTimelineOffsetRef.current = 0;
      if (queueOverride) {
        itemsRef.current = queueOverride;
        setItems(queueOverride);
      }
      indexRef.current = nextIndex;
      setIndex(nextIndex);
      setError(null);
      setSubtitleText("");
      setEpgLine(null);
      setTracks([]);
      setSelectedTracks({});
      setExternalSubtitleLoaded(false);
      setSubtitleOffsetMs(0);
      setPositionMs(0);
      setDurationMs(next.durationMs ?? 0);
      latestPlaybackRef.current = {
        positionMs: 0,
        durationMs: next.durationMs ?? 0,
      };
      hasReliablePositionRef.current = false;
      historyCheckpointRef.current = {
        key: `${next.historyType}:${next.historyStreamId}`,
        positionMs: 0,
      };
      pendingSeekRef.current = null;
      lastShownSecond.current = -1;
      prefsAppliedRef.current = false;
      window.clearTimeout(seekCommitTimer.current);
      const streamKey = `${playlist.id}:${next.historyType}:${next.historyStreamId}`;
      const savedAspect = getAspectMode(streamKey);
      setAspectModeState(savedAspect);
      player.setAspectMode(savedAspect);

      const db = await getDb();
      const persistedResume = await getResumePositionMs(
          db,
          playlist.id,
          next.historyType,
          next.historyStreamId,
        );
      const resume = modePreference
        ? requestedStartPositionRef.current ??
          resumeOverrideMs ??
          chooseResumePositionMs(next.resumeTimeMs, persistedResume)
        : resumeOverrideMs ??
          chooseResumePositionMs(next.resumeTimeMs, persistedResume);
      if (!modePreference) requestedStartPositionRef.current = resume;

      let source = {
        url: next.url,
        isLive: next.isLive,
        startPositionMs: resume,
        headers: next.userAgent ? { "User-Agent": next.userAgent } : undefined,
        mimeType: undefined as string | undefined,
      };
      if (playlist.managedByServer) {
        const server = ServerClient.connected();
        if (!server) {
          setError("Desktop connection is required for playback");
          return;
        }
        try {
          const descriptor = await server.playback(
            playlist.id,
            next.historyType,
            next.serverItemId ?? next.historyStreamId,
            next.serverEpisodeId,
            compatibilityMode,
            resume,
          );
          const effectiveStartPositionMs =
            resume ?? descriptor.startPositionMs ?? 0;
          requestedStartPositionRef.current = effectiveStartPositionMs;
          const compatibilityTimeline =
            compatibilityMode !== undefined && !descriptor.isLive;
          playbackTimelineOffsetRef.current = compatibilityTimeline
            ? effectiveStartPositionMs
            : 0;
          source = {
            url: descriptor.url,
            isLive: descriptor.isLive,
            // Desktop compatibility HLS starts at zero because FFmpeg has
            // already applied the requested content offset.
            startPositionMs: compatibilityTimeline
              ? 0
              : effectiveStartPositionMs,
            headers: undefined,
            mimeType: descriptor.mimeType,
          };
          activeServerPlaybackUrlRef.current = descriptor.url;
          if (next.isLive) {
            void server.epg(playlist.id, next.serverItemId ?? next.historyStreamId).then((programs) => {
              if (indexRef.current !== nextIndex) return;
              const now = programs.find((program) => program.nowPlaying) ?? programs[0];
              const upcoming = now ? programs[programs.indexOf(now) + 1] : undefined;
              setEpgLine([now?.title, upcoming?.title ? t("tv.epg.next_format", upcoming.title) : undefined].filter(Boolean).join(" · ") || null);
            }).catch(() => {});
          }
        } catch (reason) {
          if (compatibilityMode === "remux") {
            compatibilityStageRef.current = 2;
            setError(t("tv.playback.transcoding"));
            void openIndexRef.current(
              nextIndex,
              requestedStartPositionRef.current,
              "transcode",
            );
            return;
          }
          setError(
            reason instanceof Error
              ? reason.message
              : t("playback.error.failed_to_start"),
          );
          return;
        }
      }

      try {
        // Chromium 53 can leave HTMLMediaElement.play() pending forever while
        // the native surface reports NO_SOURCE without an error. Start the
        // watchdog before awaiting open so that silent native startup failures
        // can still advance through the managed compatibility modes.
        startupBaselineRef.current = source.startPositionMs ?? 0;
        if (playbackTimelineOffsetRef.current > 0) {
          const timelinePosition = playbackTimelineOffsetRef.current;
          latestPlaybackRef.current.positionMs = timelinePosition;
          setPositionMs(timelinePosition);
          lastShownSecond.current = Math.floor(timelinePosition / 1000);
        }
        const openPromise = player.open(source);
        startupTimerRef.current = window.setTimeout(() => {
          const activePlayer = playerRef.current;
          if (
            !activePlayer ||
            indexRef.current !== nextIndex ||
            hasPlaybackAdvanced(
              startupBaselineRef.current,
              activePlayer.getPositionMs(),
            )
          ) return;
          const fallback = playlist.managedByServer
            ? nextCompatibilityFallback(compatibilityStageRef.current)
            : null;
          if (!fallback) {
            setError("LG media startup timed out");
            return;
          }
          compatibilityStageRef.current = fallback.stage;
          setError(
            fallback.mode === "remux"
              ? t("tv.playback.compatibility")
              : t("tv.playback.transcoding"),
          );
          void openIndexRef.current(
            nextIndex,
            requestedStartPositionRef.current,
            fallback.mode,
          );
        }, PLAYER_STARTUP_TIMEOUT_MS);
        await openPromise;
        if (playlist.managedByServer && !next.isLive) {
          const server = ServerClient.connected();
          const cached = await server?.cachedSubtitle(subtitleIdentity(playlist, next));
          if (cached && indexRef.current === nextIndex) {
            const track = await player.addExternalSubtitle(cached.url, cached.title, cached.language);
            player.setSubtitleOffset(cached.offsetMs);
            player.selectTrack("TEXT", track.index);
            textDisabledRef.current = false;
            setTextDisabled(false);
            setExternalSubtitleLoaded(true);
            setSubtitleOffsetMs(cached.offsetMs);
            setTracks(player.getTracks());
            setSelectedTracks((previous) => ({ ...previous, TEXT: track.index }));
          }
        }
      } catch {
        void releaseActiveMediaSession(source.url);
        // Playback and subtitle failures are surfaced by their respective UI.
      }
    },
    [playlist, flushHistory, releaseActiveMediaSession, cancelCountdown, showControls],
  );
  const openIndexRef = useRef(openIndex);
  openIndexRef.current = openIndex;

  // Player lifecycle (mounted once; queue switches reuse the same player).
  useEffect(() => {
    const player = createPlayer();
    playerRef.current = player;
    if (containerRef.current) player.mount(containerRef.current);

    const offs = [
      player.on("statechange", ({ state: s }) => {
        setState(s);
        // Track preferences only once playback runs: AVPlay rejects
        // setSelectTrack outside PLAYING/PAUSED (INVALID_STATE).
        if (s === "playing" && !prefsAppliedRef.current) {
          prefsAppliedRef.current = true;
          const { textEnabled } = applyTrackPreferences(player);
          textDisabledRef.current = !textEnabled;
          setTextDisabled(!textEnabled);
          setTracks(player.getTracks());
        }
      }),
      player.on("prepared", ({ durationMs: d }) => {
        const current = itemsRef.current[indexRef.current];
        const timelineDuration =
          d > 0 ? d + playbackTimelineOffsetRef.current : 0;
        const effectiveDuration = Math.max(
          timelineDuration,
          current?.durationMs ?? 0,
        );
        latestPlaybackRef.current.durationMs = effectiveDuration;
        setDurationMs(effectiveDuration);
      }),
      player.on("timeupdate", ({ positionMs: p }) => {
        if (hasPlaybackAdvanced(startupBaselineRef.current, p)) {
          window.clearTimeout(startupTimerRef.current);
        }
        const timelinePosition = p + playbackTimelineOffsetRef.current;
        latestPlaybackRef.current.positionMs = timelinePosition;
        hasReliablePositionRef.current = true;
        const current = itemsRef.current[indexRef.current];
        // The native webOS video element reliably emits timeupdate while the
        // separate interval can be delayed when the TV throttles background
        // JavaScript. Persist from the media clock itself, before the OSD
        // early returns below, so hiding controls never disables resume.
        if (!current?.isLive && timelinePosition >= HISTORY_TICK_MS) {
          const key = `${current.historyType}:${current.historyStreamId}`;
          const previous = historyCheckpointRef.current;
          if (
            previous.key !== key ||
            timelinePosition - previous.positionMs >= HISTORY_TICK_MS
          ) {
            historyCheckpointRef.current = {
              key,
              positionMs: timelinePosition,
            };
            void flushHistory();
          }
        }
        // Only the seek bar consumes the clock: skip entirely while the OSD
        // is hidden, a panel covers it, or the item is live (no seek bar) —
        // otherwise the whole player tree re-rendered once per second for
        // zero visual change. showControls re-syncs the position on reveal.
        if (!controlsRef.current || panelRef.current !== "none") return;
        if (current?.isLive) return;
        // Skip while an accumulated seek is pending (optimistic position wins)
        // and only re-render when the visible second actually changes.
        if (pendingSeekRef.current !== null) return;
        const second = Math.floor(timelinePosition / 1000);
        if (second === lastShownSecond.current) return;
        lastShownSecond.current = second;
        setPositionMs(timelinePosition);
      }),
      player.on("buffering", ({ done }) => setBuffering(!done)),
      player.on("error", ({ message }) => {
        window.clearTimeout(startupTimerRef.current);
        const fallback = playlist.managedByServer
          ? nextCompatibilityFallback(compatibilityStageRef.current)
          : null;
        if (fallback) {
          compatibilityStageRef.current = fallback.stage;
          setError(
            fallback.mode === "remux"
              ? t("tv.playback.compatibility")
              : t("tv.playback.transcoding"),
          );
          void openIndexRef.current(
            indexRef.current,
            requestedStartPositionRef.current,
            fallback.mode,
          );
          return;
        }
        setError(message);
      }),
      player.on("subtitle", ({ text }) => {
        if (!textDisabledRef.current) {
          setSubtitleText(sanitizeSubtitleText(text));
        }
      }),
      player.on("ended", () => {
        const currentItems = itemsRef.current;
        const current = currentItems[indexRef.current];
        const hasNext = indexRef.current + 1 < currentItems.length;
        void flushHistory().then(() => {
          if (
            hasNext &&
            !current.isLive &&
            settings.autoPlayNextEpisode
          ) {
            startAutoAdvance();
          } else if (!hasNext) {
            pop();
          }
        });
      }),
    ];

    void openIndexRef.current(startIndex);

    const onVisibility = () => {
      if (document.hidden) player.suspend();
      else player.restore();
    };
    document.addEventListener("visibilitychange", onVisibility);

    const historyTimer = window.setInterval(() => {
      const activePlayer = playerRef.current;
      const current = itemsRef.current[indexRef.current];
      if (!activePlayer || !current) return;
      // Some older LG native-video builds advance the media clock while
      // briefly reporting a stale state. A positive VOD position is still a
      // valid checkpoint, and prevents Back from losing the latest resume
      // point just because the statechange event arrived late.
      if (
        activePlayer.getState() === "playing" ||
        (!current.isLive &&
          activePlayer.getPositionMs() + playbackTimelineOffsetRef.current > 0)
      ) {
        void flushHistory();
      }
    }, HISTORY_TICK_MS);

    return () => {
      // Snapshot while the native video is still mounted. Destroying first
      // clears its timeline, which previously let Back discard the latest
      // VOD position on webOS even after visible playback had advanced.
      const finalHistory = flushHistory();
      window.clearTimeout(startupTimerRef.current);
      window.clearInterval(historyTimer);
      document.removeEventListener("visibilitychange", onVisibility);
      offs.forEach((off) => off());
      player.destroy();
      playerRef.current = null;
      void finalHistory.finally(() => releaseActiveMediaSession());
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const startAutoAdvance = useCallback(() => {
    setCountdown(AUTO_ADVANCE_SECONDS);
    window.clearInterval(countdownTimer.current);
    countdownTimer.current = window.setInterval(() => {
      setCountdown((current) => {
        if (current === null) return null;
        if (current <= 1) {
          window.clearInterval(countdownTimer.current);
          void openIndexRef.current(indexRef.current + 1);
          return null;
        }
        return current - 1;
      });
    }, 1000);
  }, []);

  // Back priority: panel → countdown → controls → exit. Reads state via refs
  // so the interceptor registers once instead of re-stacking every countdown
  // tick / panel toggle.
  useEffect(() => {
    return registerBackInterceptor(() => {
      if (panelRef.current !== "none") {
        closePanel();
        return true;
      }
      if (countdownRef.current !== null) {
        cancelCountdown();
        pop();
        return true;
      }
      if (controlsRef.current) {
        window.clearTimeout(hideTimer.current);
        hideControls();
        return true;
      }
      void flushHistory().then(() => pop());
      return true;
    });
  }, [cancelCountdown, flushHistory, pop, hideControls, closePanel]);

  // Transport + panel keys. Panel/countdown/current-item are read through
  // refs: the listener would otherwise unbind+rebind once per countdown
  // second and on every panel toggle.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const player = playerRef.current;
      if (!player) return;
      const code = normalizeKeyCode(event);
      if (
        code >= 48 &&
        code <= 57 &&
        playlist.managedByServer &&
        (panelRef.current === "none" || panelRef.current === "channels")
      ) {
        const shortcut = shortcutsRef.current[String(code - 48)];
        if (shortcut) {
          if (panelRef.current === "channels") closePanel();
          void (async () => {
            let favoriteChannels: Array<{
              itemId: string;
              name: string;
              imageUrl?: string;
            }> = [];
            try {
              const favorites = await getFavorites(
                await getDb(),
                playlist.id,
                "live",
              );
              favoriteChannels = favorites.map((favorite) => ({
                itemId: favorite.itemId,
                name: favorite.name ?? favorite.itemId,
                imageUrl: favorite.imageURL,
              }));
            } catch {}
            const currentChannels = itemsRef.current
              .filter((entry) => entry.isLive)
              .map((entry) => ({
                itemId: entry.serverItemId ?? entry.historyStreamId,
                name: entry.title,
                imageUrl: entry.imageURL,
              }));
            const pageChannels = Object.values(shortcutsRef.current);
            const merged = mergeChannelShortcutSources(
              currentChannels,
              favoriteChannels,
              pageChannels,
              [shortcut],
            );
            const queue: PlayableItem[] = merged.map((channel) => ({
              url: "",
              title: channel.name,
              imageURL: channel.imageUrl,
              isLive: true,
              historyType: "live",
              historyStreamId: channel.itemId,
              serverItemId: channel.itemId,
            }));
            const target = Math.max(
              queue.findIndex(
                (entry) => entry.historyStreamId === shortcut.itemId,
              ),
              0,
            );
            void openIndexRef.current(
              target,
              undefined,
              undefined,
              queue,
            );
          })();
        }
        return;
      }
      const channelStep = channelStepForKeyCode(code);
      const liveQueue = itemsRef.current;
      const liveItem = liveQueue[indexRef.current];
      if (channelStep !== 0 && liveItem?.isLive && liveQueue.length > 1) {
        event.preventDefault();
        event.stopImmediatePropagation();
        if (panelRef.current !== "none") closePanel();
        void openIndexRef.current(
          (indexRef.current + channelStep + liveQueue.length) % liveQueue.length,
        );
        return;
      }
      if (panelRef.current !== "none") {
        if (
          panelRef.current === "channels" &&
          code === KEY.Blue &&
          playlist.managedByServer
        ) {
          event.preventDefault();
          event.stopImmediatePropagation();
          cycleShortcutPage();
        }
        return;
      }
      const item = items[indexRef.current];
      if (!item) return;
      if (code === KEY.Back) return;
      const colorPanel = playerPanelForColorKey(code, item.isLive);
      // Norigin's Enter callback is unreliable after it focuses a control
      // that replaced the whole toolbar on Chromium 53. Route the retry at
      // the player level while the terminal error state is visible.
      if (code === KEY.Enter && error) {
        event.preventDefault();
        event.stopImmediatePropagation();
        void openIndexRef.current(indexRef.current);
        return;
      }
      const favoriteFocused =
        getCurrentFocusKey() === PLAYER_FAV_KEY ||
        document.querySelector(
          `[data-player-control="${PLAYER_FAV_KEY}"][data-focused="true"]`,
        ) !== null;
      if (code === KEY.Enter && favoriteFocused) {
        event.preventDefault();
        event.stopImmediatePropagation();
        toggleFav();
        return;
      }
      // Next-episode countdown: OK starts the next episode immediately; the
      // other transport keys stay quiet (Back cancels via the interceptor).
      if (countdownRef.current !== null) {
        if (
          code === KEY.Enter ||
          code === KEY.MediaPlay ||
          code === KEY.MediaPlayPause
        ) {
          cancelCountdown();
          void openIndexRef.current(indexRef.current + 1);
        }
        return;
      }

      const controlsWereHidden = !controlsRef.current;
      // ←/→ while the controls were hidden reveal them WITH the seek bar
      // focused (seek intent) — but never seek blind: scrubbing only happens
      // with focus on the bar (SeekBar.onArrowPress).
      if (
        controlsWereHidden &&
        !item.isLive &&
        (code === KEY.Left || code === KEY.Right)
      ) {
        revealFocusRef.current = PLAYER_SEEK_KEY;
      }
      showControls();

      // With the overlay visible, OK belongs to the focused control (Norigin
      // onEnterPress); only with no player control focused does OK mean
      // play/pause (controls hidden → the overlay is unmounted).
      // Chromium 53 can visually focus Norigin controls while
      // getCurrentFocusKey() reports an empty/generated key. If the overlay
      // was already visible, OK belongs to that focused control; only an OK
      // that revealed a hidden overlay is the global play/pause shortcut.
      const retryFocused = document.querySelector(
        '.player-retry-button[data-focused="true"]',
      ) !== null;
      const onPlayerControl =
        (!controlsWereHidden && controlsRef.current) || retryFocused;
      if (code === KEY.MediaPlayPause) {
        togglePlay();
      } else if (code === KEY.Enter) {
        if (!onPlayerControl) togglePlay();
      } else if (code === KEY.MediaPlay) {
        player.play();
      } else if (code === KEY.MediaPause) {
        player.pause();
      } else if (code === KEY.MediaStop) {
        void flushHistory().then(() => pop());
      } else if (!item.isLive && code === KEY.MediaRewind) {
        // Dedicated media keys scrub regardless of focus.
        stepSeek(-1);
      } else if (!item.isLive && code === KEY.MediaFastForward) {
        stepSeek(1);
      } else if (colorPanel === "tracks") {
        setTracks(player.getTracks());
        setPanel("tracks");
      } else if (
        colorPanel === "channels" &&
        (items.length > 1 || playlist.managedByServer)
      ) {
        setPanel("channels");
      } else if (code === KEY.Red) {
        toggleFav();
      } else if (code === KEY.Green) {
        const current = items[indexRef.current];
        const next = nextAspectMode(getAspectMode(`${playlist.id}:${current.historyType}:${current.historyStreamId}`));
        player.setAspectMode(next);
        saveAspectMode(`${playlist.id}:${current.historyType}:${current.historyStreamId}`, next);
        setAspectModeState(next);
      }
    };
    const onKeyUp = (event: KeyboardEvent) => {
      const player = playerRef.current;
      if (!player || panelRef.current !== "none" || !controlsRef.current) return;
      const item = items[indexRef.current];
      if (!item) return;
      const code = normalizeKeyCode(event);
      if (code !== KEY.Left && code !== KEY.Right) return;

      // Norigin owns keydown on older webOS Chromium builds. Route the sparse
      // player toolbar once on key release, which it leaves untouched. The
      // seek bar keeps Left/Right for scrubbing through its own keydown path.
      const seekFocused = document.querySelector(
        '.player-seek[data-focused="true"]',
      ) !== null;
      const retryFocused = document.querySelector(
        '.player-retry-button[data-focused="true"]',
      ) !== null;
      if (seekFocused || retryFocused) return;

      const controls = [
        PLAYER_PLAY_KEY,
        ...(favoriteKeyFor(playlist, item) ? [PLAYER_FAV_KEY] : []),
        ...(item.isLive && (items.length > 1 || playlist.managedByServer)
          ? [PLAYER_CHANNELS_KEY]
          : []),
        PLAYER_TRACKS_KEY,
        PLAYER_ASPECT_KEY,
        PLAYER_INFO_KEY,
      ];
      const currentIndex = Math.min(
        horizontalFocusIndexRef.current,
        controls.length - 1,
      );
      const nextIndex = code === KEY.Right
        ? Math.min(currentIndex + 1, controls.length - 1)
        : Math.max(currentIndex - 1, 0);
      if (nextIndex !== currentIndex) {
        horizontalFocusIndexRef.current = nextIndex;
        setFocus(controls[nextIndex]);
      }
      event.preventDefault();
      event.stopImmediatePropagation();
    };
    window.addEventListener("keydown", onKeyDown, true);
    window.addEventListener("keyup", onKeyUp, true);
    return () => {
      window.removeEventListener("keydown", onKeyDown, true);
      window.removeEventListener("keyup", onKeyUp, true);
    };
  }, [items, playlist.id, playlist.managedByServer, error, cancelCountdown, closePanel, cycleShortcutPage, showControls, flushHistory, pop, stepSeek, toggleFav, togglePlay]);

  const selectTrack = useCallback((track: TrackInfo) => {
    const player = playerRef.current;
    if (!player) return;
    if (track.type === "TEXT") {
      textDisabledRef.current = false;
      setTextDisabled(false);
    }
    player.selectTrack(track.type, track.index);
    rememberTrackSelection(track);
    if (playlist.managedByServer && track.language) {
      const values = track.type === "AUDIO"
        ? { audioLanguage: track.language }
        : track.type === "TEXT"
          ? { subtitleLanguage: track.language }
          : null;
      if (values) {
        void ServerClient.connected()?.patchPreferences(playlist.id, values).catch(() => {});
      }
    }
    setSelectedTracks((prev) => ({ ...prev, [track.type]: track.index }));
  }, [playlist.id, playlist.managedByServer]);

  const disableText = useCallback(() => {
    textDisabledRef.current = true;
    setTextDisabled(true);
    setSubtitleText("");
    rememberSubtitlesOff();
    if (playlist.managedByServer) {
      void ServerClient.connected()?.patchPreferences(playlist.id, {
        subtitleLanguage: "__off__",
      }).catch(() => {});
    }
  }, [playlist.id, playlist.managedByServer]);

  const loadOnlineSubtitle = useCallback(async (descriptor: ServerSubtitleDescriptor) => {
    const player = playerRef.current;
    if (!player) return;
    try {
      const track = await player.addExternalSubtitle(
        descriptor.url,
        descriptor.title,
        descriptor.language,
      );
      player.setSubtitleOffset(descriptor.offsetMs);
      player.selectTrack("TEXT", track.index);
      textDisabledRef.current = false;
      setTextDisabled(false);
      setExternalSubtitleLoaded(true);
      setSubtitleOffsetMs(descriptor.offsetMs);
      setTracks(player.getTracks());
      setSelectedTracks((previous) => ({ ...previous, TEXT: track.index }));
      closePanel();
    } catch (reason) {
      setError(
        reason instanceof Error
          ? reason.message
          : t("tv.subtitle.load_failed"),
      );
      closePanel();
    }
  }, [closePanel]);

  const adjustSubtitleOffset = useCallback((deltaMs: number) => {
    const current = items[indexRef.current];
    if (!current) return;
    const next = Math.max(-30000, Math.min(30000, subtitleOffsetMs + deltaMs));
    playerRef.current?.setSubtitleOffset(next);
    setSubtitleOffsetMs(next);
    void ServerClient.connected()?.setSubtitleOffset(subtitleIdentity(playlist, current), next).catch(() => {});
  }, [items, playlist, subtitleOffsetMs]);


  const showChannelsButton =
    item.isLive && (items.length > 1 || playlist.managedByServer);
  const seekKey = !item.isLive ? PLAYER_SEEK_KEY : undefined;
  const firstSideKey = favKey
    ? PLAYER_FAV_KEY
    : showChannelsButton
      ? PLAYER_CHANNELS_KEY
      : PLAYER_TRACKS_KEY;
  const afterFavKey = showChannelsButton
    ? PLAYER_CHANNELS_KEY
    : PLAYER_TRACKS_KEY;
  const tracksLeftKey = showChannelsButton
    ? PLAYER_CHANNELS_KEY
    : favKey
      ? PLAYER_FAV_KEY
      : PLAYER_PLAY_KEY;
  const cycleAspect = useCallback(() => {
    const current = items[indexRef.current];
    const streamKey = `${playlist.id}:${current.historyType}:${current.historyStreamId}`;
    const next = nextAspectMode(aspectMode);
    playerRef.current?.setAspectMode(next);
    saveAspectMode(streamKey, next);
    setAspectModeState(next);
  }, [items, playlist.id, aspectMode]);

  const overlayShown =
    (controlsVisible || state !== "playing" || error !== null) &&
    panel === "none" &&
    countdown === null;
  const subtitleStyle = settings.subtitleStyle;

  return (
    <div className="player-screen">
      <div ref={containerRef} className="player-surface" />

      {subtitleText !== "" && !textDisabled && (
        <div
          className={`subtitle-overlay${overlayShown ? " raised" : ""}`}
          style={{
            fontSize: `${subtitleStyle.fontSize}px`,
            lineHeight: subtitleStyle.lineHeight,
            letterSpacing: `${subtitleStyle.letterSpacing}px`,
            wordSpacing: `${subtitleStyle.wordSpacing}px`,
            color: subtitleStyle.textColor,
            backgroundColor: subtitleStyle.backgroundColor,
            fontWeight: subtitleStyle.fontWeight,
            textAlign: subtitleStyle.textAlign,
            padding: `${subtitleStyle.padding}px`,
          }}
        >
          {subtitleText}
        </div>
      )}

      {overlayShown && (
          <div className="player-overlay">
            <div className="player-title-block">
              <h2>{item.title}</h2>
              {(item.isLive ||
                item.secondaryTitle ||
                items.length > 1) && (
                <p className="player-subtitle">
                  {item.isLive && (
                    <span className="live-badge">{t("stream.live")}</span>
                  )}
                  {(item.secondaryTitle || epgLine) && <span>{item.secondaryTitle || epgLine}</span>}
                  {items.length > 1 && (
                    <span className="queue-position">
                      {index + 1} / {items.length}
                    </span>
                  )}
                </p>
              )}
            </div>

            <div className="player-bottom-stack">
              {error ? (
                <div className="player-error-actions">
                  <p className="player-error">{error}</p>
                  <RetryButton
                    onRetry={() => void openIndexRef.current(indexRef.current)}
                  />
                </div>
              ) : (
                <>
                  {!item.isLive && (
                    <SeekBar
                      positionMs={positionMs}
                      durationMs={durationMs}
                      onStep={stepSeek}
                      onToggle={togglePlay}
                    />
                  )}
                  <div className="player-controls-row">
                    <PlayPauseButton
                      paused={state === "paused"}
                      buffering={buffering}
                      onToggle={togglePlay}
                      upKey={seekKey}
                      rightKey={firstSideKey}
                    />
                    <div className="player-side-buttons">
                      {favKey && (
                        <ChromeButton
                          focusKey={PLAYER_FAV_KEY}
                          onPress={toggleFav}
                          leftKey={PLAYER_PLAY_KEY}
                          rightKey={afterFavKey}
                          upKey={seekKey}
                        >
                          <span
                            className={`chrome-fav-heart${favorite ? " active" : ""}`}
                          >
                            ♥
                          </span>
                        </ChromeButton>
                      )}
                      {showChannelsButton && (
                        <ChromeButton
                          focusKey={PLAYER_CHANNELS_KEY}
                          onPress={() => setPanel("channels")}
                          leftKey={favKey ? PLAYER_FAV_KEY : PLAYER_PLAY_KEY}
                          rightKey={PLAYER_TRACKS_KEY}
                          upKey={seekKey}
                        >
                          ☰
                        </ChromeButton>
                      )}
                      <ChromeButton
                        focusKey={PLAYER_TRACKS_KEY}
                        onPress={() => {
                          setTracks(playerRef.current?.getTracks() ?? []);
                          setPanel("tracks");
                        }}
                        leftKey={tracksLeftKey}
                        rightKey={PLAYER_ASPECT_KEY}
                        upKey={seekKey}
                      >
                        ⚙
                      </ChromeButton>
                      <ChromeButton
                        focusKey={PLAYER_ASPECT_KEY}
                        onPress={cycleAspect}
                        leftKey={PLAYER_TRACKS_KEY}
                        rightKey={PLAYER_INFO_KEY}
                        upKey={seekKey}
                      >
                        <span
                          className="player-aspect-glyph"
                          title={`Aspect: ${aspectMode}`}
                        >
                          16:9
                        </span>
                      </ChromeButton>
                      <ChromeButton
                        focusKey={PLAYER_INFO_KEY}
                        onPress={() => setPanel("info")}
                        leftKey={PLAYER_ASPECT_KEY}
                        upKey={seekKey}
                      >
                        <span title={t("player.info.title")}>ⓘ</span>
                      </ChromeButton>
                    </div>
                  </div>
                </>
              )}
              <p className="player-hints">
                {`${t("player.tracks.title")}: ${t("tv.key.yellow")}`}
                {` · ${t("player.all_channels")}: ${t("tv.key.blue")}`}
                {` · 16:9: ${t("tv.key.green")}`}
              </p>
            </div>
          </div>
        )}

      {panel === "tracks" && (
        <Modal onDismiss={() => closePanel()}>
          <TrackSettingsPanel
            tracks={tracks}
            selected={selectedTracks}
            onSelectTrack={(track) => {
              selectTrack(track);
              closePanel();
            }}
            onDisableText={() => {
              disableText();
              closePanel();
            }}
            textDisabled={textDisabled}
            onSearchOnline={playlist.managedByServer && !item.isLive
              ? () => setPanel("subtitleSearch")
              : undefined}
            subtitleOffsetMs={externalSubtitleLoaded ? subtitleOffsetMs : undefined}
            onAdjustSubtitleOffset={externalSubtitleLoaded ? adjustSubtitleOffset : undefined}
          />
        </Modal>
      )}

      {panel === "subtitleSearch" && (
        <Modal onDismiss={() => setPanel("tracks")}>
          <OnlineSubtitlePanel
            identity={subtitleIdentity(playlist, item)}
            onLoaded={(descriptor) => void loadOnlineSubtitle(descriptor)}
          />
        </Modal>
      )}

      {panel === "info" && (
        <Modal onDismiss={closePanel}>
          <PlayerInfoPanel item={item} epgLine={epgLine} />
        </Modal>
      )}

      {panel === "channels" && (
        <LiveChannelPanel
          items={items}
          currentIndex={index}
          shortcutPages={playlist.managedByServer ? CHANNEL_SHORTCUT_PAGES : undefined}
          shortcutPage={playlist.managedByServer ? shortcutPage : undefined}
          onSelect={zapFromPanel}
          onDismiss={closePanel}
        />
      )}

      {countdown !== null && (
        <div className="autonext-overlay">
          <p>{t("player.autonext.countdown", countdown)}</p>
          <p className="autonext-target">
            {items[index + 1]?.secondaryTitle ?? items[index + 1]?.title}
          </p>
          <p className="autonext-hint">{t("tv.autonext_now")}</p>
        </div>
      )}
    </div>
  );
}
