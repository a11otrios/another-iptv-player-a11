import { useCallback, useEffect, useRef, useState } from "react";
import {
  doesFocusableExist,
  setFocus,
} from "@noriginmedia/norigin-spatial-navigation";
import { withTimeout } from "./services/asyncTimeout";
import { exitApp } from "./env/platform";
import { getDb } from "./data/db";
import { getPlaylist } from "./data/playlistRepo";
import { getCategories } from "./data/catalogRepo";
import { settings } from "./data/settings";
import { dispatchBack } from "./navigation/backHandler";
import { KEY, normalizeKeyCode } from "./navigation/keys";
import {
  ScreenDescriptor,
  topScreen,
  useNavigation,
} from "./navigation/NavigationStack";
import { ScreenLayer } from "./navigation/ScreenLayer";
import { PlaylistListScreen } from "./ui/screens/PlaylistListScreen";
import { AddPlaylistScreen } from "./ui/screens/AddPlaylistScreen";
import { DashboardScreen } from "./ui/screens/DashboardScreen";
import { CategoryGridScreen } from "./ui/screens/CategoryGridScreen";
import { MovieDetailScreen } from "./ui/screens/MovieDetailScreen";
import { SeriesDetailScreen } from "./ui/screens/SeriesDetailScreen";
import { PlayerScreen } from "./ui/screens/PlayerScreen";
import { ToolchainScreen } from "./ui/screens/ToolchainScreen";
import { PlayerSpikeScreen } from "./ui/screens/PlayerSpikeScreen";
import { registerBackInterceptor } from "./navigation/backHandler";
import { useLanguageVersion } from "./i18n/react";
import { t } from "./i18n";
import { ServerClient } from "./api/serverClient";
import { syncServerLibrary } from "./data/serverSync";
import {
  LaunchLocation,
  resumableLocation,
  screenFromLaunchLocation,
} from "./navigation/launchResume";
import "./ui/styles/app.css";

function renderScreen(screen: ScreenDescriptor) {
  switch (screen.name) {
    case "playlists":
      return <PlaylistListScreen />;
    case "addPlaylist":
      return <AddPlaylistScreen />;
    case "dashboard":
      return <DashboardScreen playlist={screen.playlist} />;
    case "categoryGrid":
      return (
        <CategoryGridScreen
          playlist={screen.playlist}
          kind={screen.kind}
          categoryId={screen.categoryId}
          title={screen.title}
        />
      );
    case "movieDetail":
      return (
        <MovieDetailScreen playlist={screen.playlist} vodId={screen.vodId} />
      );
    case "seriesDetail":
      return (
        <SeriesDetailScreen
          playlist={screen.playlist}
          seriesId={screen.seriesId}
        />
      );
    case "player":
      return (
        <PlayerScreen
          playlist={screen.playlist}
          items={screen.items}
          startIndex={screen.startIndex}
        />
      );
    case "toolchain":
      return <ToolchainScreen />;
    case "spike":
      return <SpikeWithBack />;
  }
}

async function launchLocationExists(
  location: LaunchLocation,
  playlistId: string,
): Promise<boolean> {
  const db = await getDb();
  switch (location.name) {
    case "dashboard":
      return true;
    // Server-managed libraries deliberately keep their item catalog on the
    // desktop. Detail screens fetch these records on demand, so their absence
    // from IndexedDB must not prevent a valid saved location from restoring.
    case "movieDetail":
    case "seriesDetail":
      return true;
    case "categoryGrid":
      if (location.kind === "m3uGroup") return true;
      return (await getCategories(db, playlistId, location.kind)).some(
        (category) => category.categoryId === location.categoryId,
      );
  }
}

export function App() {
  const { stack, pop, reset, pendingFocusRestore, consumeFocusRestore } =
    useNavigation();
  const languageVersion = useLanguageVersion();
  const [booted, setBooted] = useState(false);
  const [exitArmed, setExitArmed] = useState(false);
  const exitTimer = useRef<number | undefined>(undefined);

  // Cold start restores the last browsed screen, but deliberately never
  // reopens a player: unexpected auto-play is especially disruptive on TV.
  useEffect(() => {
    void (async () => {
      const client = await ServerClient.restore();
      const lastId = settings.lastPlaylistId;
      const savedLocation = settings.lastLaunchLocation as LaunchLocation | null;
      const playlistId = savedLocation?.playlistId ?? lastId;
      try {
        if (playlistId) {
          const db = await withTimeout(getDb(), 3000);
          const playlist = await withTimeout(getPlaylist(db, playlistId), 3000);
          if (playlist) {
            const dashboard: ScreenDescriptor = { name: "dashboard", playlist };
            const canRestore =
              savedLocation?.playlistId === playlist.id &&
              (await withTimeout(launchLocationExists(savedLocation, playlist.id), 3000));
            // Seed the playlist list below the dashboard so Back remains
            // predictable after a resumed category/detail screen.
            if (canRestore && savedLocation.name !== "dashboard") {
              reset(
                { name: "playlists" },
                dashboard,
                screenFromLaunchLocation(savedLocation, playlist),
              );
            } else {
              reset({ name: "playlists" }, dashboard);
            }
          }
        }
      } catch {
        // Keep the playlist/recovery controls reachable when TV storage fails.
      } finally {
        setBooted(true);
      }
      if (client) {
        try {
          await syncServerLibrary(client);
        } catch (error) {
          // Cached snapshots remain usable while the desktop is temporarily off.
          console.warn("[server] refresh failed; using cached library", error);
        }
      }
    })();
  }, [reset]);

  // Persist the last non-player screen. If the app is closed during playback,
  // the detail/category beneath it is the sensible, non-playing destination.
  useEffect(() => {
    if (!booted) return;
    for (let index = stack.length - 1; index >= 0; index -= 1) {
      const location = resumableLocation(stack[index].screen);
      if (location) {
        settings.lastLaunchLocation = location;
        return;
      }
    }
  }, [booted, stack]);

  // After a pop the covered screen is still mounted: return focus to the
  // exact control the user left (captured at push time).
  useEffect(() => {
    if (!pendingFocusRestore) return;
    const target = pendingFocusRestore;
    requestAnimationFrame(() => {
      if (doesFocusableExist(target)) setFocus(target);
      consumeFocusRestore();
    });
  }, [pendingFocusRestore, consumeFocusRestore]);

  const onKeyDown = useCallback(
    (event: KeyboardEvent) => {
      if (normalizeKeyCode(event) !== KEY.Back) return;
      event.preventDefault();
      if (dispatchBack()) {
        setExitArmed(false);
        return;
      }
      if (stack.length > 1) {
        // Dismissing a dashboard clears the auto-open id (iOS parity),
        // whether it was pushed from the list or seeded at cold start.
        if (topScreen(stack).name === "dashboard") {
          settings.lastPlaylistId = null;
          settings.lastLaunchLocation = null;
        }
        pop();
        return;
      }
      if (exitArmed) {
        exitApp();
      } else {
        setExitArmed(true);
        window.clearTimeout(exitTimer.current);
        exitTimer.current = window.setTimeout(() => setExitArmed(false), 2000);
      }
    },
    [stack, pop, exitArmed],
  );

  useEffect(() => {
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onKeyDown]);

  if (!booted) {
    return <div className="boot-screen" />;
  }

  return (
    // Keyed by language so a language switch re-renders every t() call site.
    <div className="app-shell" key={`lang-${languageVersion}`}>
      {stack.map((entry, index) => (
        <ScreenLayer
          key={`${index}:${entry.screen.name}`}
          active={index === stack.length - 1}
        >
          {renderScreen(entry.screen)}
        </ScreenLayer>
      ))}

      {exitArmed && <div className="exit-toast">{t("tv.exit_hint")}</div>}
    </div>
  );
}

/** Adapter keeping the phase-1 spike screen's stop-on-back behavior. */
function SpikeWithBack() {
  const interceptor = useRef<(() => boolean) | null>(null);
  const register = useCallback((fn: (() => boolean) | null) => {
    interceptor.current = fn;
  }, []);
  useEffect(() => {
    return registerBackInterceptor(() => interceptor.current?.() ?? false);
  }, []);
  return <PlayerSpikeScreen registerBackInterceptor={register} />;
}
