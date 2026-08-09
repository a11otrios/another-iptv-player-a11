export const CHANNEL_SHORTCUT_PAGES = ["A", "S", "D", "F", "G"] as const;

export type ChannelShortcutPage = (typeof CHANNEL_SHORTCUT_PAGES)[number];

export function nextChannelShortcutPage(
  current: ChannelShortcutPage,
): ChannelShortcutPage {
  const index = CHANNEL_SHORTCUT_PAGES.indexOf(current);
  return CHANNEL_SHORTCUT_PAGES[(index + 1) % CHANNEL_SHORTCUT_PAGES.length];
}
