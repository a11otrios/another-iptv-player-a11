import { describe, expect, it } from "vitest";
import {
  hasPlaybackAdvanced,
  nextCompatibilityFallback,
  preferredInitialCompatibilityMode,
} from "../src/player/compatibilityFallback";

describe("preferredInitialCompatibilityMode", () => {
  const legacyWebOS =
    "Mozilla/5.0 (Web0S; Linux/SmartTV) Chrome/53.0.2785.34 Safari/537.36";

  it("starts managed Matroska VOD with remuxing on legacy webOS", () => {
    expect(
      preferredInitialCompatibilityMode({
        managedByServer: true,
        isLive: false,
        containerExtension: ".MKV",
        userAgent: legacyWebOS,
      }),
    ).toBe("remux");
  });

  it("keeps direct playback for modern webOS, live TV, and MP4", () => {
    expect(
      preferredInitialCompatibilityMode({
        managedByServer: true,
        isLive: false,
        containerExtension: "mkv",
        userAgent: legacyWebOS.replace("Chrome/53", "Chrome/79"),
      }),
    ).toBeNull();
    expect(
      preferredInitialCompatibilityMode({
        managedByServer: true,
        isLive: true,
        containerExtension: "mkv",
        userAgent: legacyWebOS,
      }),
    ).toBeNull();
    expect(
      preferredInitialCompatibilityMode({
        managedByServer: true,
        isLive: false,
        containerExtension: "mp4",
        userAgent: legacyWebOS,
      }),
    ).toBeNull();
  });
});

describe("hasPlaybackAdvanced", () => {
  it("does not mistake a resume seek for forward playback", () => {
    expect(hasPlaybackAdvanced(564_000, 564_000)).toBe(false);
    expect(hasPlaybackAdvanced(564_000, 564_249)).toBe(false);
    expect(hasPlaybackAdvanced(564_000, 564_250)).toBe(true);
  });

  it("requires progress from the beginning too", () => {
    expect(hasPlaybackAdvanced(0, 0)).toBe(false);
    expect(hasPlaybackAdvanced(0, 300)).toBe(true);
  });
});

describe("nextCompatibilityFallback", () => {
  it("advances proxy to remux and then transcode", () => {
    expect(nextCompatibilityFallback(0)).toEqual({ stage: 1, mode: "remux" });
    expect(nextCompatibilityFallback(1)).toEqual({ stage: 2, mode: "transcode" });
  });

  it("stops after the bounded transcode attempt", () => {
    expect(nextCompatibilityFallback(2)).toBeNull();
    expect(nextCompatibilityFallback(3)).toBeNull();
  });
});
