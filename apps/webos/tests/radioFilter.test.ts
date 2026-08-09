import { describe, expect, it } from "vitest";
import { isLikelyRadioStation } from "@/models/radioFilter";

describe("radio station filter", () => {
  it("recognizes explicit radio categories and station names", () => {
    expect(isLikelyRadioStation("Music One", "UK | Radio")).toBe(true);
    expect(isLikelyRadioStation("Athens FM 98.4", "Music")).toBe(true);
    expect(isLikelyRadioStation("Station", "ΡΑΔΙΟΦΩΝΟ")).toBe(true);
  });

  it("keeps ordinary television channels", () => {
    expect(isLikelyRadioStation("Cartoon One", "Children")).toBe(false);
    expect(isLikelyRadioStation("ERT 1 HD", "General")).toBe(false);
  });
});
