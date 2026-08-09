import { beforeEach, describe, expect, it } from "vitest";
import {
  DEFAULT_SUBTITLE_STYLE,
  settings,
  SubtitleStylePreference,
} from "../src/data/settings";

const values = new Map<string, string>();
Object.defineProperty(globalThis, "localStorage", {
  configurable: true,
  value: {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
    removeItem: (key: string) => values.delete(key),
  },
});

describe("subtitle style preference", () => {
  beforeEach(() => values.clear());

  it("uses TV-safe defaults and persists a desktop-synchronized style", () => {
    expect(settings.subtitleStyle).toEqual(DEFAULT_SUBTITLE_STYLE);
    const style: SubtitleStylePreference = {
      ...DEFAULT_SUBTITLE_STYLE,
      fontSize: 42,
      lineHeight: 1.6,
      textColor: "rgba(255, 240, 0, 1)",
      textAlign: "left",
    };

    settings.subtitleStyle = style;

    expect(settings.subtitleStyle).toEqual(style);
  });
});
