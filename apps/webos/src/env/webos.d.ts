interface AudioTrack {
  enabled: boolean;
  readonly id: string;
  readonly kind: string;
  readonly label: string;
  readonly language: string;
}

interface AudioTrackList {
  readonly length: number;
  [index: number]: AudioTrack;
  addEventListener?(type: "addtrack" | "change", listener: EventListener): void;
}

interface HTMLMediaElement {
  readonly audioTracks?: AudioTrackList;
}

interface Window {
  webOS?: {
    platformBack?: () => void;
    service?: {
      request(uri: string, options: {
        method: string;
        parameters?: Record<string, unknown>;
        onSuccess?: (response: unknown) => void;
        onFailure?: (error: unknown) => void;
      }): unknown;
    };
  };
}
