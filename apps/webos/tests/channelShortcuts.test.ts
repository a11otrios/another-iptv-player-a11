import { describe, expect, it } from "vitest";
import {
  CHANNEL_SHORTCUT_PAGES,
  mergeChannelShortcutSources,
  nextChannelShortcutPage,
} from "../src/models/channelShortcuts";

describe("channel shortcut pages", () => {
  it("cycles through every desktop shortcut page and wraps to A", () => {
    expect(CHANNEL_SHORTCUT_PAGES).toEqual(["A", "S", "D", "F", "G"]);
    expect(nextChannelShortcutPage("A")).toBe("S");
    expect(nextChannelShortcutPage("S")).toBe("D");
    expect(nextChannelShortcutPage("D")).toBe("F");
    expect(nextChannelShortcutPage("F")).toBe("G");
    expect(nextChannelShortcutPage("G")).toBe("A");
  });

  it("combines category, favorite, and shortcut channels without duplicates", () => {
    expect(
      mergeChannelShortcutSources(
        [{ itemId: "category", name: "Category channel" }],
        [
          { itemId: "favorite", name: "Favorite channel" },
          { itemId: "category", name: "Duplicate" },
        ],
        [{ itemId: "shortcut", name: "Shortcut channel" }],
      ).map((item) => item.itemId),
    ).toEqual(["category", "favorite", "shortcut"]);
  });
});
