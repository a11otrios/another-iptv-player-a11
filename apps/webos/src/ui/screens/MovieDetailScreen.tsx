import { useCallback, useEffect, useMemo, useState } from "react";
import {
  FocusContext,
  useFocusable,
} from "@noriginmedia/norigin-spatial-navigation";
import { getDb } from "../../data/db";
import {
  PlaylistRecord,
  VodInfoRecord,
  VodStreamRecord,
  WatchHistoryRecord,
} from "../../data/records";
import { getVodById } from "../../data/catalogRepo";
import { getVodInfo, saveVodInfo } from "../../data/seriesInfoRepo";
import { isFavorite, toggleFavorite } from "../../data/favoritesRepo";
import { getHistoryEntryWithServerFallback } from "../../data/watchHistoryRepo";
import { XtreamClient } from "../../api/xtreamClient";
import { PlaybackUrlBuilder } from "../../api/playbackUrlBuilder";
import { mediaDurationMs, PlayableItem } from "../../models/playable";
import { useNavigation } from "../../navigation/NavigationStack";
import { useScreenActive } from "../../navigation/ScreenLayer";
import { KEY, normalizeKeyCode } from "../../navigation/keys";
import { getLanguage, t } from "../../i18n";
import { useCachedImage } from "../../services/imageCache";
import { Button } from "../components/TextField";
import { ServerClient } from "../../api/serverClient";
import { openExternalUrl } from "../../env/platform";
import { serverItemToRecord } from "../../data/serverCatalog";

/** "2019-05-14" → "2019"; anything that doesn't start with a year is dropped. */
function releaseYear(date: string | undefined): string | undefined {
  const year = date?.slice(0, 4);
  return year && /^\d{4}$/.test(year) ? year : undefined;
}

export function trailerUrl(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  if (!normalized) return undefined;
  if (/^https?:\/\//i.test(normalized)) return normalized;
  return `https://www.youtube.com/watch?v=${encodeURIComponent(normalized)}`;
}

export function formatHistoryTime(valueMs: number): string {
  const totalSeconds = Math.max(0, Math.floor(valueMs / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return hours > 0
    ? `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
    : `${minutes}:${String(seconds).padStart(2, "0")}`;
}

export function historyProgressPercent(
  positionMs: number,
  durationMs: number,
): number | undefined {
  if (!Number.isFinite(durationMs) || durationMs <= 0) return undefined;
  return Math.max(0, Math.min(100, (positionMs / durationMs) * 100));
}

function formatHistoryDate(valueMs: number): string | undefined {
  if (!Number.isFinite(valueMs) || valueMs <= 0) return undefined;
  const date = new Date(valueMs);
  if (Number.isNaN(date.getTime())) return undefined;
  return date.toLocaleString(getLanguage(), {
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function MovieDetailScreen({
  playlist,
  vodId,
}: {
  playlist: PlaylistRecord;
  vodId: string | number;
}) {
  const { push } = useNavigation();
  const [movie, setMovie] = useState<VodStreamRecord | null>(null);
  const [details, setDetails] = useState<VodInfoRecord | null>(null);
  // Backdrop waits for the get_vod_info attempt to settle: showing the
  // blurred poster first and swapping to the real art looks inconsistent.
  const [detailsSettled, setDetailsSettled] = useState(false);
  const [historyEntry, setHistoryEntry] = useState<WatchHistoryRecord | undefined>(
    undefined,
  );
  const [resumeMs, setResumeMs] = useState<number | undefined>(undefined);
  const [favorite, setFavorite] = useState(false);

  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      let record = await getVodById(db, playlist.id, vodId);
      if (!record && playlist.managedByServer) {
        try {
          const remote = await ServerClient.connected()?.item(playlist.id, "vod", vodId);
          if (remote) record = serverItemToRecord(remote) as VodStreamRecord;
        } catch {
          // Enriched details may still be available from the local cache.
        }
      }
      if (!cancelled && record) setMovie(record);

      const history = await getHistoryEntryWithServerFallback(
        db,
        playlist.id,
        "vod",
        String(vodId),
        playlist.managedByServer === true,
      );
      if (!cancelled) {
        setHistoryEntry(history);
        setResumeMs(
          history && history.lastTimeMs >= 5000
            ? history.lastTimeMs
            : undefined,
        );
      }
      const fav = await isFavorite(db, playlist.id, "vod", String(vodId));
      if (!cancelled) setFavorite(fav);

      // Lazy get_vod_info enrichment (iOS metadataLoaded pattern); the base
      // catalog fields keep the screen usable when the fetch fails.
      // `duration === undefined` also marks records cached before the field
      // existed — refresh those once.
      let cached = await getVodInfo(db, playlist.id, vodId);
      if (playlist.managedByServer) {
        try {
          const remote = await ServerClient.connected()?.vod(playlist.id, vodId);
          if (remote) {
            cached = {
              id: `${playlist.id}_${vodId}`,
              playlistId: playlist.id,
              vodId,
              ...remote,
              fetchedAt: Date.now(),
            };
            try {
              await saveVodInfo(db, cached);
            } catch (error) {
              console.warn("[vod] could not cache managed movie info", error);
            }
          }
        } catch {
          // Base catalog metadata remains usable while enrichment is offline.
        }
        if (!cancelled) {
          if (cached) setDetails(cached);
          setDetailsSettled(true);
        }
        return;
      }
      if (cached && cached.duration === undefined) cached = undefined;
      if (!cached) {
        try {
          const client = new XtreamClient(playlist);
          const remote = await client.getVodInfo(vodId as number);
          cached = {
            id: `${playlist.id}_${vodId}`,
            playlistId: playlist.id,
            vodId,
            plot: remote.info?.plot,
            cast: remote.info?.cast,
            director: remote.info?.director,
            genre: remote.info?.genre,
            releaseDate: remote.info?.releaseDate,
            rating: remote.info?.rating,
            backdropPath: remote.info?.backdropPath,
            youtubeTrailer: remote.info?.youtubeTrailer,
            duration: remote.info?.duration ?? "",
            durationSecs: remote.info?.durationSecs,
            tmdbId: remote.info?.tmdbId,
            containerExtension: remote.movieData?.containerExtension,
            fetchedAt: Date.now(),
          };
          await saveVodInfo(db, cached);
        } catch {
          if (!cancelled) setDetailsSettled(true);
          return; // catalog fields already shown
        }
      }
      if (!cancelled) {
        if (cached) setDetails(cached);
        setDetailsSettled(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [playlist, vodId]);

  useEffect(() => {
    if (movie) focusSelf();
  }, [movie, focusSelf]);

  const toggleFav = useCallback(() => {
    const previous = favorite;
    setFavorite(!previous);
    void (async () => {
      try {
        const db = await getDb();
        setFavorite(
          await toggleFavorite(
            db,
            playlist.id,
            "vod",
            String(vodId),
            movie?.name ?? String(vodId),
            movie?.icon,
          ),
        );
      } catch {
        setFavorite(previous);
      }
    })();
  }, [playlist.id, vodId, movie, favorite]);

  const screenActive = useScreenActive();
  useEffect(() => {
    if (!screenActive) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (normalizeKeyCode(event) !== KEY.Red) return;
      toggleFav();
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [toggleFav, screenActive]);

  // Stays mounted under the player layer; re-read the state on return there
  // (the player's heart button can toggle this movie meanwhile).
  useEffect(() => {
    if (!screenActive) return;
    let cancelled = false;
    void (async () => {
      const db = await getDb();
      const [fav, history] = await Promise.all([
        isFavorite(db, playlist.id, "vod", String(vodId)),
        getHistoryEntryWithServerFallback(
          db,
          playlist.id,
          "vod",
          String(vodId),
          playlist.managedByServer === true,
        ),
      ]);
      if (!cancelled) {
        setFavorite(fav);
        setHistoryEntry(history);
        setResumeMs(
          history && history.lastTimeMs >= 5000
            ? history.lastTimeMs
            : undefined,
        );
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [screenActive, playlist.id, playlist.managedByServer, vodId]);

  const urls = useMemo(() => new PlaybackUrlBuilder(playlist), [playlist]);

  // Real backdrop art renders sharp; a portrait poster only works as an
  // ambient color field, so the fallback stays blurred — and only once the
  // details attempt settled (no poster→backdrop photo swap).
  const heroArt = details?.backdropPath?.[0];
  const backdrop = useCachedImage(
    heroArt ?? (detailsSettled ? movie?.icon : undefined),
  );

  const play = useCallback(
    (fromMs?: number) => {
      if (!movie) return;
      const item: PlayableItem = {
        url: playlist.managedByServer ? "" : urls.movieUrl(
          movie.streamId as number,
          details?.containerExtension ?? movie.containerExtension,
        ),
        title: movie.name,
        imageURL: movie.icon,
        isLive: false,
        historyType: "vod",
        historyStreamId: String(movie.streamId),
        serverItemId: playlist.managedByServer ? String(movie.streamId) : undefined,
        containerExtension:
          details?.containerExtension ?? movie.containerExtension,
        resumeTimeMs: fromMs ?? 0,
        durationMs: mediaDurationMs(details?.duration, details?.durationSecs),
      };
      push({ name: "player", playlist, items: [item], startIndex: 0 });
    },
    [movie, details, urls, push, playlist],
  );

  const openTrailer = useCallback(() => {
    const url = trailerUrl(details?.youtubeTrailer);
    if (url) void openExternalUrl(url);
  }, [details?.youtubeTrailer]);

  if (!movie) {
    // ref stays attached even while loading: a registered focusable without
    // a DOM node breaks Norigin's layout math.
    return (
      <p ref={ref} className="screen-hint">
        {t("common.loading")}
      </p>
    );
  }

  const rating = details?.rating ?? movie.rating;
  // iOS parity: the panel's raw runtime string ("01:29:00") wins — many
  // panels put junk in duration_secs; minutes math is only the fallback.
  const durationLabel = details?.duration?.trim()
    ? details.duration.trim()
    : details?.durationSecs !== undefined && details.durationSecs > 0
      ? t("tv.minutes_format", Math.round(details.durationSecs / 60))
      : undefined;
  const metaChips = [
    releaseYear(details?.releaseDate),
    details?.genre,
    durationLabel,
    rating ? `★ ${rating}` : undefined,
  ].filter((chip): chip is string => !!chip);
  const metadataDurationMs = mediaDurationMs(
    details?.duration,
    details?.durationSecs,
  );
  const historyDurationMs =
    historyEntry && historyEntry.durationMs > 0
      ? historyEntry.durationMs
      : metadataDurationMs ?? 0;
  const historyPositionMs = historyEntry
    ? Math.min(
        historyEntry.lastTimeMs,
        historyDurationMs > 0 ? historyDurationMs : historyEntry.lastTimeMs,
      )
    : 0;
  const historyProgress = historyProgressPercent(
    historyPositionMs,
    historyDurationMs,
  );
  const watchedAt = historyEntry
    ? formatHistoryDate(historyEntry.lastWatchedAt)
    : undefined;
  const remainingMs = Math.max(0, historyDurationMs - historyPositionMs);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="screen detail-screen movie-detail">
        {backdrop && (
          <div className={`detail-backdrop${heroArt ? " sharp" : ""}`}>
            <img src={backdrop} alt="" />
            <div className="detail-backdrop-scrim" />
          </div>
        )}
        <div className="detail-body">
          <h1 className="detail-title">{movie.name}</h1>
          <p className="detail-meta-line">
            {metaChips.length > 0 && <span>{metaChips.join("\u2002·\u2002")}</span>}
            <span className={`detail-fav${favorite ? " active" : ""}`}>♥</span>
          </p>
          {details?.plot && (
            <p className="detail-plot clamp-3">{details.plot}</p>
          )}
          {details?.director && (
            <p className="detail-credit clamp-1">
              {t("movie.director")}: {details.director}
            </p>
          )}
          {details?.cast && (
            <p className="detail-credit clamp-1">
              {t("movie.cast")}: {details.cast}
            </p>
          )}
          {historyEntry && historyEntry.lastTimeMs > 0 && (
            <section className="detail-history" aria-label={t("history.title")}>
              <div className="detail-history-header">
                <span className="detail-history-title">{t("history.title")}</span>
                <span className="detail-history-time">
                  {formatHistoryTime(historyPositionMs)}
                  {historyDurationMs > 0 &&
                    ` / ${formatHistoryTime(historyDurationMs)}`}
                </span>
              </div>
              {historyProgress !== undefined && (
                <div className="detail-history-progress">
                  <span
                    className="detail-history-progress-fill"
                    style={{ width: `${historyProgress}%` }}
                  />
                </div>
              )}
              <div className="detail-history-meta">
                {watchedAt && (
                  <span>
                    {t("detail.watched")} {watchedAt}
                  </span>
                )}
                {historyDurationMs > 0 && remainingMs > 0 && (
                  <span>{t("detail.remaining_format", formatHistoryTime(remainingMs))}</span>
                )}
              </div>
            </section>
          )}
          <div className="detail-actions">
            {resumeMs !== undefined && (
              <Button
                primary
                label={`${t("detail.resume")} (${Math.floor(resumeMs / 60000)}:${String(Math.floor((resumeMs % 60000) / 1000)).padStart(2, "0")})`}
                onSelect={() => play(resumeMs)}
              />
            )}
            <Button
              primary={resumeMs === undefined}
              label={
                resumeMs !== undefined ? t("detail.restart") : t("movie.play")
              }
              onSelect={() => play(0)}
            />
            <Button
              label={`♥ ${t(favorite ? "favorites.remove" : "favorites.add")}`}
              onSelect={toggleFav}
            />
            {trailerUrl(details?.youtubeTrailer) && (
              <Button label={t("movie.trailer")} onSelect={openTrailer} />
            )}
          </div>
          <p className="detail-key-hint">{t("tv.favorite_hint")}</p>
        </div>
      </div>
    </FocusContext.Provider>
  );
}
