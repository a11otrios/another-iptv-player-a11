import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { WebOSVideoAdapter } from "../src/player/WebOSVideoAdapter";

class FakeTrackList<T extends EventTarget> extends EventTarget {
  [index: number]: T;
  length = 0;

  add(track: T): void {
    this[this.length++] = track;
    this.dispatchEvent(new Event("addtrack"));
  }
}

class FakeTextTrack extends EventTarget {
  language = "eng";
  label = "English";
  mode: TextTrackMode = "disabled";
  cues: TextTrackCueList | null = null;
  activeCues: TextTrackCueList | null = null;
}

class FakeTrackElement extends EventTarget {
  kind = "";
  label = "";
  srclang = "";
  src = "";
  default = false;
  readonly track = new FakeTextTrack();
}

class FakeSourceElement {
  src = "";
  type = "";
}

let nextVideoPlayResult: Promise<void> | undefined;

class FakeVideo extends EventTarget {
  autoplay = false;
  playsInline = false;
  paused = true;
  seeking = false;
  private playbackTime = 0;
  blockBackwardSeek = false;
  duration = Number.NaN;
  readyState = 0;
  error: { code: number } | null = null;
  style: Record<string, string> = {};
  audioTracks = new FakeTrackList<EventTarget & { enabled: boolean; language: string; label: string }>();
  textTracks = new FakeTrackList<FakeTextTrack>();
  children: Array<FakeSourceElement | FakeTrackElement> = [];
  loadCalls = 0;
  playCalls = 0;
  removed = false;
  playResult: Promise<void>;

  get currentTime(): number { return this.playbackTime; }
  set currentTime(value: number) {
    if (this.blockBackwardSeek && value < this.playbackTime) {
      this.seeking = true;
      return;
    }
    this.playbackTime = value;
  }

  constructor() {
    super();
    this.playResult = nextVideoPlayResult ?? Promise.resolve();
    nextVideoPlayResult = undefined;
  }

  appendChild(child: FakeSourceElement | FakeTrackElement): void {
    this.children.push(child);
    if (child instanceof FakeTrackElement) this.textTracks.add(child.track);
  }

  load(): void { this.loadCalls += 1; }
  play(): Promise<void> { this.playCalls += 1; this.paused = false; return this.playResult; }
  pause(): void { this.paused = true; this.dispatchEvent(new Event("pause")); }
  canPlayType(type: string): CanPlayTypeResult {
    return type === "video/x-matroska" ? "" : "probably";
  }
  removeAttribute(): void {}
  remove(): void { this.removed = true; }
  set innerHTML(_value: string) { this.children = []; }
}

class FakeContainer {
  children: FakeVideo[] = [];
  appendChild(video: FakeVideo): void { this.children.push(video); }
}

const videos: FakeVideo[] = [];

function currentVideo(): FakeVideo {
  return videos[videos.length - 1];
}

function deferred(): { promise: Promise<void>; reject: (reason: Error) => void } {
  let reject!: (reason: Error) => void;
  const promise = new Promise<void>((_resolve, rejectPromise) => { reject = rejectPromise; });
  return { promise, reject };
}

beforeEach(() => {
  vi.useFakeTimers();
  videos.length = 0;
  nextVideoPlayResult = undefined;
  vi.stubGlobal("window", {
    setInterval: globalThis.setInterval,
    clearInterval: globalThis.clearInterval,
    setTimeout: globalThis.setTimeout,
    clearTimeout: globalThis.clearTimeout,
  });
  vi.stubGlobal("HTMLMediaElement", { HAVE_FUTURE_DATA: 3 });
  vi.stubGlobal("document", {
    createElement(tag: string) {
      if (tag === "video") {
        const video = new FakeVideo();
        videos.push(video);
        return video;
      }
      if (tag === "source") return new FakeSourceElement();
      if (tag === "track") return new FakeTrackElement();
      throw new Error(`Unexpected element: ${tag}`);
    },
  });
});

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
});

describe("WebOSVideoAdapter", () => {
  it("opens each stream on a fresh native video element with an explicit MIME type", async () => {
    const adapter = new WebOSVideoAdapter();
    const container = new FakeContainer();
    adapter.mount(container as unknown as HTMLElement);
    const mounted = currentVideo();

    await adapter.open({ url: "http://desktop/live/1", mimeType: "application/vnd.apple.mpegurl", isLive: true });

    const opened = currentVideo();
    expect(opened).not.toBe(mounted);
    expect(mounted.removed).toBe(true);
    expect(opened.children[0]).toMatchObject({
      src: "http://desktop/live/1",
      type: "application/vnd.apple.mpegurl",
    });
    expect(opened.loadCalls).toBe(1);
    expect(opened.playCalls).toBe(1);
    expect(adapter.getState()).toBe("preparing");
  });

  it("omits MIME types the LG media element rejects so native probing can run", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);

    await adapter.open({
      url: "http://desktop/stream/episode",
      mimeType: "video/x-matroska",
      isLive: false,
    });

    expect(currentVideo().children[0]).toMatchObject({
      src: "http://desktop/stream/episode",
      type: "",
    });
  });

  it("translates metadata and playback events and restores a VOD position", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);
    const prepared = vi.fn();
    const states = vi.fn();
    adapter.on("prepared", prepared);
    adapter.on("statechange", states);

    await adapter.open({ url: "http://desktop/vod/1", isLive: false, startPositionMs: 42_000 });
    const video = currentVideo();
    video.duration = 100;
    video.dispatchEvent(new Event("loadedmetadata"));
    video.dispatchEvent(new Event("playing"));

    expect(video.currentTime).toBe(42);
    expect(prepared).toHaveBeenCalledWith({ durationMs: 100_000 });
    expect(adapter.getState()).toBe("playing");
    adapter.pause();
    expect(adapter.getState()).toBe("paused");
    expect(states).toHaveBeenCalledWith({ state: "paused" });
  });

  it("selects native audio and subtitle tracks", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);
    await adapter.open({ url: "http://desktop/vod/1", isLive: false });
    const video = currentVideo();
    video.audioTracks.add(Object.assign(new EventTarget(), { enabled: true, language: "eng", label: "English" }));
    video.audioTracks.add(Object.assign(new EventTarget(), { enabled: false, language: "deu", label: "Deutsch" }));
    const english = new FakeTextTrack();
    const german = new FakeTextTrack();
    german.language = "deu";
    german.label = "Deutsch";
    video.textTracks.add(english);
    video.textTracks.add(german);

    adapter.selectTrack("AUDIO", 1);
    adapter.selectTrack("TEXT", 1);

    expect(video.audioTracks[0].enabled).toBe(false);
    expect(video.audioTracks[1].enabled).toBe(true);
    expect(english.mode).toBe("disabled");
    expect(german.mode).toBe("hidden");
    expect(adapter.getTracks()).toHaveLength(4);
  });

  it("does not duplicate subtitle events when track metadata refreshes", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);
    await adapter.open({ url: "http://desktop/vod/1", isLive: false });
    const video = currentVideo();
    const textTrack = new FakeTextTrack();
    textTrack.activeCues = { 0: { text: "Hello" }, length: 1 } as unknown as TextTrackCueList;
    video.textTracks.add(textTrack);
    video.dispatchEvent(new Event("loadedmetadata"));
    video.dispatchEvent(new Event("loadedmetadata"));
    const subtitles = vi.fn();
    adapter.on("subtitle", subtitles);

    textTrack.dispatchEvent(new Event("cuechange"));

    expect(subtitles).toHaveBeenCalledTimes(1);
    expect(subtitles).toHaveBeenCalledWith({ text: "Hello" });
  });

  it("ignores a play rejection from a stream that has already been replaced", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);
    const obsolete = deferred();
    nextVideoPlayResult = obsolete.promise;
    const firstOpen = adapter.open({ url: "http://desktop/live/old", isLive: true });

    await adapter.open({ url: "http://desktop/live/new", isLive: true });
    currentVideo().dispatchEvent(new Event("playing"));
    obsolete.reject(new Error("obsolete stream failed"));
    await expect(firstOpen).rejects.toThrow("obsolete stream failed");

    expect(adapter.getState()).toBe("playing");
  });

  it("recreates a playing VOD element and restores its position after suspend", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);
    await adapter.open({ url: "http://desktop/family/vod", isLive: false });
    const playing = currentVideo();
    playing.currentTime = 37;
    playing.dispatchEvent(new Event("playing"));

    adapter.suspend();
    expect(playing.removed).toBe(true);

    adapter.restore();
    const restored = currentVideo();
    restored.duration = 100;
    restored.dispatchEvent(new Event("loadedmetadata"));

    expect(restored.children[0]).toMatchObject({
      src: "http://desktop/family/vod",
    });
    expect(restored.currentTime).toBe(37);
    expect(restored.playCalls).toBe(1);
  });

  it("recreates the native element at the target when a backward seek wedges", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);
    await adapter.open({ url: "http://desktop/family/vod", isLive: false });
    const stuck = currentVideo();
    stuck.duration = 120;
    stuck.currentTime = 80;
    stuck.dispatchEvent(new Event("playing"));
    stuck.blockBackwardSeek = true;

    await adapter.seekTo(50_000);
    expect(currentVideo()).toBe(stuck);

    await vi.advanceTimersByTimeAsync(4000);
    const recovered = currentVideo();
    expect(recovered).not.toBe(stuck);
    recovered.duration = 120;
    recovered.dispatchEvent(new Event("loadedmetadata"));

    expect(recovered.currentTime).toBe(50);
    expect(recovered.playCalls).toBe(1);
  });

  it("keeps the native element when a backward seek completes normally", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);
    await adapter.open({ url: "http://desktop/family/vod", isLive: false });
    const video = currentVideo();
    video.duration = 120;
    video.currentTime = 80;
    video.dispatchEvent(new Event("playing"));

    await adapter.seekTo(50_000);
    video.dispatchEvent(new Event("seeked"));
    await vi.advanceTimersByTimeAsync(4000);

    expect(currentVideo()).toBe(video);
    expect(video.currentTime).toBe(50);
  });

  it("replaces a frozen element twice, then emits a terminal stall error", async () => {
    const adapter = new WebOSVideoAdapter();
    adapter.mount(new FakeContainer() as unknown as HTMLElement);
    const errors = vi.fn();
    adapter.on("error", errors);
    await adapter.open({ url: "http://desktop/live/1", isLive: true });

    for (let cycle = 0; cycle < 3; cycle++) {
      const video = currentVideo();
      video.readyState = 0;
      video.currentTime = 0;
      video.paused = false;
      video.dispatchEvent(new Event("playing"));
      await vi.advanceTimersByTimeAsync(12_000);
    }

    expect(videos).toHaveLength(4);
    expect(errors).toHaveBeenCalledWith({ message: "LG media pipeline stalled" });
    expect(adapter.getState()).toBe("idle");
  });
});
