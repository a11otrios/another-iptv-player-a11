import { describe, expect, it } from "vitest";
import {
  CHANNEL_SHORTCUT_PAGES,
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
});
