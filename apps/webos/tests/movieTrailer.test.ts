import { describe, expect, it } from "vitest";
import { trailerUrl } from "../src/ui/screens/MovieDetailScreen";

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
