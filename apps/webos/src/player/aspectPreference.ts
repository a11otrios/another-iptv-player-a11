import { AspectMode } from "./PlayerPort";

const PREFIX = "aiptv.aspect.v1.";

export function getAspectMode(streamKey: string): AspectMode {
  const value = localStorage.getItem(PREFIX + streamKey);
  return value === "cover" || value === "fill" ? value : "contain";
}

export function setAspectMode(streamKey: string, mode: AspectMode): void {
  localStorage.setItem(PREFIX + streamKey, mode);
}

export function nextAspectMode(mode: AspectMode): AspectMode {
  return mode === "contain" ? "cover" : mode === "cover" ? "fill" : "contain";
}
