export const CHANNEL_SHORTCUT_PAGES = ["A", "S", "D", "F", "G"] as const;

export type ChannelShortcutPage = (typeof CHANNEL_SHORTCUT_PAGES)[number];

export interface ChannelShortcutItem {
  itemId: string;
  name: string;
  imageUrl?: string;
}

/** Preserves source order while removing duplicate live-channel identities. */
export function mergeChannelShortcutSources(
  ...sources: ReadonlyArray<ReadonlyArray<ChannelShortcutItem>>
): ChannelShortcutItem[] {
  const seen = new Set<string>();
  const merged: ChannelShortcutItem[] = [];
  for (const source of sources) {
    for (const item of source) {
      if (seen.has(item.itemId)) continue;
      seen.add(item.itemId);
      merged.push(item);
    }
  }
  return merged;
}

export function nextChannelShortcutPage(
  current: ChannelShortcutPage,
): ChannelShortcutPage {
  const index = CHANNEL_SHORTCUT_PAGES.indexOf(current);
  return CHANNEL_SHORTCUT_PAGES[(index + 1) % CHANNEL_SHORTCUT_PAGES.length];
}
