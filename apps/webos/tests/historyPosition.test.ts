import { describe, expect, it } from "vitest";
import { resolveHistoryPositionMs } from "../src/data/watchHistoryRepo";

describe("resolveHistoryPositionMs", () => {
  it("prefers an advancing native clock over a stale event value", () => {
    expect(resolveHistoryPositionMs(131_582, 0, true)).toBe(131_582);
  });

  it("retains the last event position while the native clock is zero", () => {
    expect(resolveHistoryPositionMs(0, 74_098, true)).toBe(74_098);
  });

  it("does not invent a checkpoint before playback advances", () => {
    expect(resolveHistoryPositionMs(0, 0, true)).toBe(0);
    expect(resolveHistoryPositionMs(Number.NaN, 12_000, false)).toBe(0);
  });
});
