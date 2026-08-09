import { useCallback, useEffect, useState } from "react";
import { FocusContext, useFocusable } from "@noriginmedia/norigin-spatial-navigation";
import {
  ServerClient,
  ServerSubtitleDescriptor,
  ServerSubtitleIdentity,
  ServerSubtitleResult,
} from "../../api/serverClient";
import { Button, TextField } from "../components/TextField";
import { t } from "../../i18n";

function SubtitleResultButton({
  result,
  onSelect,
}: {
  result: ServerSubtitleResult;
  onSelect: () => void;
}) {
  const { ref, focused } = useFocusable({ onEnterPress: onSelect });
  return (
    <div ref={ref} className={`subtitle-result${focused ? " focused" : ""}`}>
      <span className="subtitle-result-title">{result.releaseName || result.title}</span>
      <span className="subtitle-result-meta">
        {[result.language.toUpperCase(), result.format.toUpperCase(), `${result.downloadCount} downloads`]
          .filter(Boolean)
          .join(" · ")}
      </span>
    </div>
  );
}

export function OnlineSubtitlePanel({
  identity,
  onLoaded,
}: {
  identity: ServerSubtitleIdentity;
  onLoaded: (descriptor: ServerSubtitleDescriptor) => void;
}) {
  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });
  const [query, setQuery] = useState(identity.title);
  const [results, setResults] = useState<ServerSubtitleResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const search = useCallback(async (searchText = query) => {
    const server = ServerClient.connected();
    if (!server) return;
    setLoading(true);
    setError(null);
    try {
      setResults(await server.searchSubtitles(identity, searchText));
      requestAnimationFrame(() => focusSelf());
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("common.unknown_error"));
    } finally {
      setLoading(false);
    }
  }, [identity, query, focusSelf]);

  useEffect(() => {
    void search(identity.title);
    // Search once for the current item. Manual retries use the button below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [identity.playlistId, identity.itemId, identity.episodeId]);

  const download = useCallback(async (result: ServerSubtitleResult) => {
    const server = ServerClient.connected();
    if (!server) return;
    setLoading(true);
    setError(null);
    try {
      onLoaded(await server.downloadSubtitle(identity, result));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : t("common.unknown_error"));
    } finally {
      setLoading(false);
    }
  }, [identity, onLoaded]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="subtitle-search-panel">
        <h2>{t("player.subtitle_online.title")}</h2>
        <div className="subtitle-search-form">
          <TextField
            label={t("player.subtitle_online.query")}
            value={query}
            onChange={setQuery}
          />
          <Button label={t("search.title")} onSelect={() => void search()} primary />
        </div>
        {loading && <p className="screen-hint">{t("common.loading")}</p>}
        {error && <p className="form-error">{error}</p>}
        {!loading && !error && results.length === 0 && (
          <p className="screen-hint">{t("player.subtitle_online.empty")}</p>
        )}
        <div className="subtitle-results">
          {results.map((result) => (
            <SubtitleResultButton
              key={`${result.fileId}-${result.subtitleId}`}
              result={result}
              onSelect={() => void download(result)}
            />
          ))}
        </div>
      </div>
    </FocusContext.Provider>
  );
}
