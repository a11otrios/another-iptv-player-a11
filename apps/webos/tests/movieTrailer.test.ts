import { describe, expect, it } from "vitest";
import {
  formatHistoryTime,
  historyProgressPercent,
  trailerUrl,
} from "../src/ui/screens/MovieDetailScreen";

describe("movie trailer URL", () => {
  it("turns an Xtream YouTube key into a watch URL", () => {
    expect(trailerUrl("abc_123")).toBe(
      "https://www.youtube.com/watch?v=abc_123",
    );
  });

  it("keeps a provider-supplied absolute URL", () => {
    expect(trailerUrl("https://example.com/trailer")).toBe(
      "https://example.com/trailer",
    );
  });

  it("hides the action when no trailer is available", () => {
    expect(trailerUrl("  ")).toBeUndefined();
  });
});

describe("movie detail history", () => {
  it("formats checkpoints for short and long movies", () => {
    expect(formatHistoryTime(94_900)).toBe("1:34");
    expect(formatHistoryTime(3_661_000)).toBe("1:01:01");
  });

  it("clamps progress and omits it when duration is unknown", () => {
    expect(historyProgressPercent(25_000, 100_000)).toBe(25);
    expect(historyProgressPercent(110_000, 100_000)).toBe(100);
    expect(historyProgressPercent(25_000, 0)).toBeUndefined();
  });
});
