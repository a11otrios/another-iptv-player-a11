import { isWebOS } from "../env/platform";

// LG remote key codes. Arrows/Enter and color/media keys arrive as keydown.
export const KEY = {
  Enter: 13,
  Escape: 27, // desktop dev only, mapped to Back
  Left: 37,
  Up: 38,
  Right: 39,
  Down: 40,
  Back: 461,
  MediaPlayPause: 10252,
  MediaPlay: 415,
  MediaPause: 19,
  MediaStop: 413,
  MediaRewind: 412,
  MediaFastForward: 417,
  Red: 403,
  Green: 404,
  Yellow: 405,
  Blue: 406,
  ChannelUp: 427,
  ChannelDown: 428,
  PageUp: 33,
  PageDown: 34,
} as const;

/**
 * Returns the live-channel queue delta for programme/page keys. LG documents
 * Channel +/- as unavailable to web apps, but older firmware/remotes can emit
 * either the 427/428 TV codes or 33/34 PageUp/PageDown codes.
 */
export function channelStepForKeyCode(code: number): -1 | 0 | 1 {
  if (code === KEY.ChannelUp || code === KEY.PageUp) return 1;
  if (code === KEY.ChannelDown || code === KEY.PageDown) return -1;
  return 0;
}

export function playerPanelForColorKey(
  code: number,
  _isLive: boolean,
): "tracks" | "channels" | null {
  // Keep colour keys consistent regardless of the playing media type:
  // Yellow opens track/subtitle settings and Blue opens the channel list.
  if (code === KEY.Yellow) return "tracks";
  if (code === KEY.Blue) return "channels";
  return null;
}

export function registerTVKeys(): void {
  // webOS delivers remote keys as regular keydown events; no registration API.
}

/**
 * Normalizes a keydown to an app key code. Desktop dev mappings:
 * Escape → Back, r → Red, g → Green, y → Yellow, b → Blue, space → PlayPause.
 */
export function normalizeKeyCode(event: KeyboardEvent): number {
  if (isWebOS()) return event.keyCode;
  // Don't remap letters while typing in an input field.
  const editing =
    event.target instanceof HTMLElement && event.target.tagName === "INPUT";
  if (event.keyCode === KEY.Escape) return KEY.Back;
  if (!editing) {
    if (event.keyCode === 82) return KEY.Red; // r
    if (event.keyCode === 71) return KEY.Green; // g
    if (event.keyCode === 89) return KEY.Yellow; // y
    if (event.keyCode === 66) return KEY.Blue; // b
    if (event.keyCode === 32) return KEY.MediaPlayPause; // space
    if (event.keyCode === 33) return KEY.ChannelUp; // PageUp
    if (event.keyCode === 34) return KEY.ChannelDown; // PageDown
  }
  return event.keyCode;
}
