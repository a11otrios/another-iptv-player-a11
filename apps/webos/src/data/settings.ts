// Typed localStorage wrapper for app-global settings (the iOS UserDefaults
// equivalents). Playlist-scoped data lives in IndexedDB instead.

const PREFIX = "aiptv.";

export interface SubtitleStylePreference {
  fontSize: number;
  lineHeight: number;
  letterSpacing: number;
  wordSpacing: number;
  textColor: string;
  backgroundColor: string;
  fontWeight: number;
  textAlign: "left" | "right" | "center" | "justify" | "start" | "end";
  padding: number;
}

export const DEFAULT_SUBTITLE_STYLE: SubtitleStylePreference = {
  fontSize: 32,
  lineHeight: 1.4,
  letterSpacing: 0,
  wordSpacing: 0,
  textColor: "rgba(255, 255, 255, 1)",
  backgroundColor: "rgba(0, 0, 0, 0.667)",
  fontWeight: 400,
  textAlign: "center",
  padding: 24,
};

interface SettingsShape {
  lastPlaylistId: string | null;
  language: string | null; // null = follow system
  dashboardTab: number;
  autoPlayNextEpisode: boolean;
  hideRadioStations: boolean;
  preferredAudioLanguage: string | null;
  preferredSubtitleLanguage: string | null;
  subtitleStyle: SubtitleStylePreference;
}

const DEFAULTS: SettingsShape = {
  lastPlaylistId: null,
  language: null,
  dashboardTab: 0,
  autoPlayNextEpisode: true,
  hideRadioStations: false,
  preferredAudioLanguage: null,
  preferredSubtitleLanguage: null,
  subtitleStyle: DEFAULT_SUBTITLE_STYLE,
};

function read<K extends keyof SettingsShape>(key: K): SettingsShape[K] {
  try {
    const raw = localStorage.getItem(PREFIX + key);
    if (raw === null) return DEFAULTS[key];
    return JSON.parse(raw) as SettingsShape[K];
  } catch {
    return DEFAULTS[key];
  }
}

function write<K extends keyof SettingsShape>(
  key: K,
  value: SettingsShape[K],
): void {
  try {
    if (value === null) {
      localStorage.removeItem(PREFIX + key);
    } else {
      localStorage.setItem(PREFIX + key, JSON.stringify(value));
    }
  } catch (err) {
    console.warn(`[settings] failed to persist ${key}`, err);
  }
}

export const settings = {
  get lastPlaylistId() {
    return read("lastPlaylistId");
  },
  set lastPlaylistId(value: string | null) {
    write("lastPlaylistId", value);
  },
  get language() {
    return read("language");
  },
  set language(value: string | null) {
    write("language", value);
  },
  get dashboardTab() {
    return read("dashboardTab");
  },
  set dashboardTab(value: number) {
    write("dashboardTab", value);
  },
  get autoPlayNextEpisode() {
    return read("autoPlayNextEpisode");
  },
  set autoPlayNextEpisode(value: boolean) {
    write("autoPlayNextEpisode", value);
  },
  get hideRadioStations() {
    return read("hideRadioStations");
  },
  set hideRadioStations(value: boolean) {
    write("hideRadioStations", value);
  },
  get preferredAudioLanguage() {
    return read("preferredAudioLanguage");
  },
  set preferredAudioLanguage(value: string | null) {
    write("preferredAudioLanguage", value);
  },
  get preferredSubtitleLanguage() {
    return read("preferredSubtitleLanguage");
  },
  set preferredSubtitleLanguage(value: string | null) {
    write("preferredSubtitleLanguage", value);
  },
  get subtitleStyle() {
    return { ...DEFAULT_SUBTITLE_STYLE, ...read("subtitleStyle") };
  },
  set subtitleStyle(value: SubtitleStylePreference) {
    write("subtitleStyle", value);
  },
};
