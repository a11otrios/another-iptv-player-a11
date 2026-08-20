export type CompatibilityMode = "remux" | "transcode";

export interface CompatibilityFallback {
  stage: 1 | 2;
  mode: CompatibilityMode;
}

export interface InitialCompatibilityContext {
  managedByServer: boolean;
  isLive: boolean;
  containerExtension?: string;
  userAgent: string;
}

/** Legacy webOS Chromium is unreliable with native Matroska VOD playback. */
export function preferredInitialCompatibilityMode({
  managedByServer,
  isLive,
  containerExtension,
  userAgent,
}: InitialCompatibilityContext): CompatibilityMode | null {
  if (!managedByServer || isLive || !/(?:Web0S|webOS)/i.test(userAgent)) {
    return null;
  }
  const chromeMajor = Number(/Chrome\/(\d+)/i.exec(userAgent)?.[1]);
  if (!Number.isFinite(chromeMajor) || chromeMajor >= 68) return null;
  const extension = (containerExtension ?? "")
    .trim()
    .toLowerCase()
    .replace(/^\./, "");
  return extension === "mkv" || extension === "matroska" ? "remux" : null;
}

/** A resume seek is not proof of playback; the native clock must move on. */
export function hasPlaybackAdvanced(
  baselineMs: number,
  currentPositionMs: number,
  minimumProgressMs = 250,
): boolean {
  return (
    Number.isFinite(baselineMs) &&
    Number.isFinite(currentPositionMs) &&
    currentPositionMs >= baselineMs + minimumProgressMs
  );
}

/** Two bounded compatibility attempts after direct proxy playback fails. */
export function nextCompatibilityFallback(
  currentStage: number,
): CompatibilityFallback | null {
  if (currentStage >= 2) return null;
  const stage = currentStage + 1 as 1 | 2;
  return { stage, mode: stage === 1 ? "remux" : "transcode" };
}
