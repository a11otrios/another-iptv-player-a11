import { describe, expect, it } from "vitest";
import { nextAspectMode } from "../src/player/aspectPreference";

describe("aspect mode cycle", () => {
  it("cycles original, crop, stretch, and back", () => {
    expect(nextAspectMode("contain")).toBe("cover");
    expect(nextAspectMode("cover")).toBe("fill");
    expect(nextAspectMode("fill")).toBe("contain");
  });
});
