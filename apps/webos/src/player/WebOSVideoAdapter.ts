import {
  PlaybackSource,
  PlayerEventEmitter,
  PlayerEventMap,
  PlayerEventListener,
  PlayerPort,
  PlayerState,
  TrackInfo,
  TrackType,
  AspectMode,
} from "./PlayerPort";

/** LG-native media adapter informed by lennylxx/webos-iptv-player. */
export class WebOSVideoAdapter implements PlayerPort {
  private static readonly STALL_POLL_MS = 3000;
  private static readonly STALL_TICKS_BEFORE_RELOAD = 4;
  private static readonly MAX_STALL_RELOADS = 2;

  private readonly events = new PlayerEventEmitter();
  private container: HTMLElement | null = null;
  private video: HTMLVideoElement | null = null;
  private state: PlayerState = "idle";
  private source: PlaybackSource | null = null;
  private resumePositionMs = 0;
  private resumeAfterSuspend = false;
  private aspectMode: AspectMode = "contain";
  private stallTimer: number | undefined;
  private lastStallPosition = -1;
  private frozenTicks = 0;
  private stallReloads = 0;
  private subtitleOffsetMs = 0;
  private playbackEpoch = 0;
  private readonly observedTextTracks = new WeakSet<TextTrack>();

  mount(container: HTMLElement): void {
    this.container = container;
    this.replaceVideo();
  }

  async open(source: PlaybackSource): Promise<void> {
    if (!this.container) throw new Error("mount() must be called before open()");
    const epoch = ++this.playbackEpoch;
    this.source = source;
    this.resumePositionMs = source.startPositionMs ?? 0;
    this.subtitleOffsetMs = 0;
    this.stallReloads = 0;
    this.stopStallWatchdog();
    this.replaceVideo();
    const video = this.video!;
    this.setState("preparing");

    // webOS classifies extensionless/proxied streams more reliably when an
    // explicit source MIME is present.
    this.attachSource(video, source);
    video.load();
    try {
      await video.play();
    } catch (reason) {
      if (epoch === this.playbackEpoch && video === this.video) this.setState("idle");
      throw reason;
    }
  }

  play(): void { void this.video?.play(); }
  pause(): void { this.video?.pause(); this.stopStallWatchdog(); }

  stop(): void {
    this.playbackEpoch += 1;
    this.stopStallWatchdog();
    this.source = null;
    this.resumeAfterSuspend = false;
    this.resumePositionMs = 0;
    this.replaceVideo();
    this.setState("idle");
  }

  async seekTo(positionMs: number): Promise<void> {
    if (this.video) this.video.currentTime = Math.max(positionMs, 0) / 1000;
  }

  getPositionMs(): number { return this.video ? Math.floor(this.video.currentTime * 1000) : 0; }
  getDurationMs(): number { return this.video && isFinite(this.video.duration) ? Math.floor(this.video.duration * 1000) : 0; }
  getState(): PlayerState { return this.state; }

  getTracks(): TrackInfo[] {
    const result: TrackInfo[] = [];
    const audio = this.video?.audioTracks;
    if (audio) for (let i = 0; i < audio.length; i++) result.push({ type: "AUDIO", index: i, language: audio[i].language, label: audio[i].label || `Audio ${i + 1}` });
    const text = this.video?.textTracks;
    if (text) for (let i = 0; i < text.length; i++) result.push({ type: "TEXT", index: i, language: text[i].language, label: text[i].label || `Subtitles ${i + 1}` });
    return result;
  }

  selectTrack(type: TrackType, index: number): void {
    if (type === "AUDIO") {
      const tracks = this.video?.audioTracks;
      if (!tracks || index < 0 || index >= tracks.length) return;
      for (let i = 0; i < tracks.length; i++) tracks[i].enabled = i === index;
    } else if (type === "TEXT") {
      const tracks = this.video?.textTracks;
      if (!tracks || index < 0 || index >= tracks.length) return;
      for (let i = 0; i < tracks.length; i++) tracks[i].mode = i === index ? "hidden" : "disabled";
    }
  }

  addExternalSubtitle(url: string, label: string, language?: string): Promise<TrackInfo> {
    const video = this.video;
    if (!video) return Promise.reject(new Error("Player is not mounted"));
    return new Promise((resolve, reject) => {
      const element = document.createElement("track");
      element.kind = "subtitles";
      element.label = label;
      element.srclang = language || "und";
      element.src = url;
      element.default = true;
      const timeout = window.setTimeout(() => reject(new Error("Subtitle timed out")), 15000);
      element.addEventListener("load", () => {
        window.clearTimeout(timeout);
        element.track.mode = "hidden";
        this.applySubtitleOffset(element.track, this.subtitleOffsetMs);
        this.emitTrackChange();
        const list = video.textTracks;
        let index = 0;
        for (; index < list.length; index++) if (list[index] === element.track) break;
        resolve({ type: "TEXT", index, language, label });
      }, { once: true });
      element.addEventListener("error", () => {
        window.clearTimeout(timeout);
        reject(new Error("Subtitle could not be loaded"));
      }, { once: true });
      video.appendChild(element);
    });
  }

  setSubtitleOffset(offsetMs: number): void {
    const deltaMs = offsetMs - this.subtitleOffsetMs;
    this.subtitleOffsetMs = offsetMs;
    const tracks = this.video?.textTracks;
    if (!tracks || deltaMs === 0) return;
    for (let i = 0; i < tracks.length; i++) this.applySubtitleOffset(tracks[i], deltaMs);
  }

  setAspectMode(mode: AspectMode): void {
    this.aspectMode = mode;
    if (this.video) this.video.style.objectFit = mode;
  }

  suspend(): void {
    if (!this.video || !this.source || this.resumeAfterSuspend) return;
    this.resumeAfterSuspend = !this.video.paused;
    this.resumePositionMs = this.getPositionMs();
    if (this.resumeAfterSuspend) {
      this.stopStallWatchdog();
      this.replaceVideo();
    }
  }

  restore(): void {
    if (!this.resumeAfterSuspend || !this.source) return;
    this.resumeAfterSuspend = false;
    void this.open({ ...this.source, startPositionMs: this.resumePositionMs });
  }

  on<K extends keyof PlayerEventMap>(event: K, listener: PlayerEventListener<K>): () => void { return this.events.on(event, listener); }

  destroy(): void {
    this.playbackEpoch += 1;
    this.stopStallWatchdog();
    this.source = null;
    this.releaseVideo();
    this.container = null;
    this.events.removeAll();
    this.state = "idle";
  }

  private replaceVideo(): void {
    const container = this.container;
    if (!container) return;
    this.releaseVideo();
    const video = document.createElement("video");
    video.autoplay = true;
    video.playsInline = true;
    video.style.width = "100%";
    video.style.height = "100%";
    video.style.background = "#000";
    video.style.objectFit = this.aspectMode;
    this.bind(video);
    container.appendChild(video);
    this.video = video;
  }

  private releaseVideo(): void {
    const old = this.video;
    if (!old) return;
    old.pause();
    old.removeAttribute("src");
    old.innerHTML = "";
    old.load();
    old.remove();
    this.video = null;
  }

  private bind(video: HTMLVideoElement): void {
    video.addEventListener("loadedmetadata", () => {
      if (this.resumePositionMs > 5000 && isFinite(video.duration) && video.duration > 0) {
        video.currentTime = Math.min(this.resumePositionMs / 1000, Math.max(video.duration - 1, 0));
        this.resumePositionMs = 0;
      }
      this.events.emit("prepared", { durationMs: this.getDurationMs() });
      this.emitTrackChange();
    });
    video.audioTracks?.addEventListener?.("addtrack", () => this.emitTrackChange());
    video.textTracks?.addEventListener("addtrack", () => this.emitTrackChange());
    video.addEventListener("timeupdate", () => this.events.emit("timeupdate", { positionMs: this.getPositionMs() }));
    video.addEventListener("waiting", () => this.events.emit("buffering", { done: false }));
    video.addEventListener("playing", () => {
      this.events.emit("buffering", { done: true });
      this.setState("playing");
      this.startStallWatchdog();
    });
    video.addEventListener("pause", () => {
      this.stopStallWatchdog();
      if (this.state === "playing") this.setState("paused");
    });
    video.addEventListener("ended", () => {
      this.stopStallWatchdog();
      this.events.emit("ended", {});
    });
    video.addEventListener("error", () => {
      this.stopStallWatchdog();
      this.setState("idle");
      this.events.emit("error", { message: video.error ? `LG media error ${video.error.code}` : "LG media error" });
    });
  }

  private attachSource(video: HTMLVideoElement, source: PlaybackSource): void {
    const child = document.createElement("source");
    child.src = source.url;
    if (source.mimeType && video.canPlayType(source.mimeType)) {
      child.type = source.mimeType;
    }
    video.appendChild(child);
  }

  /**
   * LG's native pipeline can freeze without emitting an error. This follows the
   * recovery pattern proven by lennylxx/webos-iptv-player: detect a stopped
   * clock with insufficient buffered data, replace the video element, and
   * eventually let the screen advance to its proxy/remux fallback.
   */
  private startStallWatchdog(): void {
    this.stopStallWatchdog();
    this.lastStallPosition = this.video?.currentTime ?? -1;
    this.stallTimer = window.setInterval(() => this.checkForStall(), WebOSVideoAdapter.STALL_POLL_MS);
  }

  private stopStallWatchdog(): void {
    if (this.stallTimer !== undefined) window.clearInterval(this.stallTimer);
    this.stallTimer = undefined;
    this.frozenTicks = 0;
  }

  private checkForStall(): void {
    const video = this.video;
    if (!video || video.paused || video.seeking) return;
    if (video.currentTime > this.lastStallPosition || video.readyState >= HTMLMediaElement.HAVE_FUTURE_DATA) {
      this.lastStallPosition = video.currentTime;
      this.frozenTicks = 0;
      if (video.currentTime > 0) this.stallReloads = 0;
      return;
    }
    this.lastStallPosition = video.currentTime;
    this.frozenTicks += 1;
    if (this.frozenTicks < WebOSVideoAdapter.STALL_TICKS_BEFORE_RELOAD) return;
    this.frozenTicks = 0;
    if (this.stallReloads >= WebOSVideoAdapter.MAX_STALL_RELOADS) {
      this.stopStallWatchdog();
      this.setState("idle");
      this.events.emit("error", { message: "LG media pipeline stalled" });
      return;
    }
    this.stallReloads += 1;
    void this.reloadAfterStall();
  }

  private async reloadAfterStall(): Promise<void> {
    const source = this.source;
    if (!source || !this.container) return;
    const epoch = this.playbackEpoch;
    const positionMs = source.isLive ? 0 : this.getPositionMs();
    this.stopStallWatchdog();
    this.replaceVideo();
    const video = this.video!;
    this.resumePositionMs = positionMs;
    this.attachSource(video, source);
    video.load();
    try {
      await video.play();
    } catch {
      if (epoch === this.playbackEpoch && video === this.video) {
        this.setState("idle");
        this.events.emit("error", { message: "LG media pipeline reload failed" });
      }
    }
  }

  private emitTrackChange(): void {
    const tracks = this.video?.textTracks;
    if (tracks) for (let i = 0; i < tracks.length; i++) {
      if (this.observedTextTracks.has(tracks[i])) continue;
      this.observedTextTracks.add(tracks[i]);
      tracks[i].addEventListener("cuechange", () => {
        const cue = tracks[i].activeCues?.[0] as VTTCue | undefined;
        this.events.emit("subtitle", { text: cue?.text ?? "" });
      });
    }
  }

  private applySubtitleOffset(track: TextTrack, deltaMs: number): void {
    const cues = track.cues;
    if (!cues || deltaMs === 0) return;
    const delta = deltaMs / 1000;
    for (let i = 0; i < cues.length; i++) {
      cues[i].startTime = Math.max(0, cues[i].startTime + delta);
      cues[i].endTime = Math.max(cues[i].startTime, cues[i].endTime + delta);
    }
  }

  private setState(state: PlayerState): void { if (state !== this.state) { this.state = state; this.events.emit("statechange", { state }); } }
}
