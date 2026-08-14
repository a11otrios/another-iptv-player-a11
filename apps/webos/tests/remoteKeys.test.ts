import { describe, expect, it } from "vitest";
import {
  channelStepForKeyCode,
  KEY,
  playerPanelForColorKey,
} from "../src/navigation/keys";

describe("programme channel keys", () => {
  it("accepts TV and legacy page key codes without using D-pad arrows", () => {
    expect(channelStepForKeyCode(KEY.ChannelUp)).toBe(1);
    expect(channelStepForKeyCode(KEY.PageUp)).toBe(1);
    expect(channelStepForKeyCode(KEY.ChannelDown)).toBe(-1);
    expect(channelStepForKeyCode(KEY.PageDown)).toBe(-1);
    expect(channelStepForKeyCode(KEY.Up)).toBe(0);
    expect(channelStepForKeyCode(KEY.Down)).toBe(0);
  });
});

describe("player color keys", () => {
  it("opens tracks with Yellow and channels with Blue for all playback", () => {
    expect(playerPanelForColorKey(KEY.Yellow, true)).toBe("tracks");
    expect(playerPanelForColorKey(KEY.Yellow, false)).toBe("tracks");
    expect(playerPanelForColorKey(KEY.Blue, true)).toBe("channels");
    expect(playerPanelForColorKey(KEY.Blue, false)).toBe("channels");
  });
});
