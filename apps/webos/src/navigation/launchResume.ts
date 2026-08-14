import type { CatalogKind, PlaylistRecord } from "../data/records";
import type { ScreenDescriptor } from "./NavigationStack";

export type LaunchLocation =
  | { name: "dashboard"; playlistId: string }
  | {
      name: "categoryGrid";
      playlistId: string;
      kind: CatalogKind | "m3uGroup";
      categoryId: string;
      title: string;
    }
  | { name: "movieDetail"; playlistId: string; vodId: string }
  | { name: "seriesDetail"; playlistId: string; seriesId: string };

/** Keeps only serializable, non-playing navigation state between launches. */
export function resumableLocation(screen: ScreenDescriptor): LaunchLocation | null {
  switch (screen.name) {
    case "dashboard":
      return { name: "dashboard", playlistId: screen.playlist.id };
    case "categoryGrid":
      return {
        name: "categoryGrid",
        playlistId: screen.playlist.id,
        kind: screen.kind,
        categoryId: screen.categoryId,
        title: screen.title,
      };
    case "movieDetail":
      return {
        name: "movieDetail",
        playlistId: screen.playlist.id,
        vodId: String(screen.vodId),
      };
    case "seriesDetail":
      return {
        name: "seriesDetail",
        playlistId: screen.playlist.id,
        seriesId: String(screen.seriesId),
      };
    default:
      return null;
  }
}

export function screenFromLaunchLocation(
  location: LaunchLocation,
  playlist: PlaylistRecord,
): ScreenDescriptor {
  switch (location.name) {
    case "dashboard":
      return { name: "dashboard", playlist };
    case "categoryGrid":
      return { ...location, playlist };
    case "movieDetail":
      return { name: "movieDetail", playlist, vodId: location.vodId };
    case "seriesDetail":
      return { name: "seriesDetail", playlist, seriesId: location.seriesId };
  }
}
