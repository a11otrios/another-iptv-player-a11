import { describe, expect, it } from "vitest";
import { PlaylistRecord } from "@/data/records";
import {
  resumableLocation,
  screenFromLaunchLocation,
} from "@/navigation/launchResume";

const playlist: PlaylistRecord = {
  id: "p1", name: "Playlist", type: "xtream", serverURL: "http://example.test",
  username: "u", password: "p", filterAdultContent: false, createdAt: 0,
};

describe("launch resume", () => {
  it("serializes a category screen without playlist credentials", () => {
    expect(resumableLocation({
      name: "categoryGrid", playlist, kind: "vod", categoryId: "12", title: "Movies",
    })).toEqual({
      name: "categoryGrid", playlistId: "p1", kind: "vod", categoryId: "12", title: "Movies",
    });
  });

  it("does not persist the player as a launch destination", () => {
    expect(resumableLocation({ name: "player", playlist, items: [], startIndex: 0 })).toBeNull();
  });

  it("rebuilds a serializable movie detail location with the current playlist", () => {
    expect(screenFromLaunchLocation(
      { name: "movieDetail", playlistId: "p1", vodId: "88" }, playlist,
    )).toEqual({ name: "movieDetail", playlist, vodId: "88" });
  });
});
