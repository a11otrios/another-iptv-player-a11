import { useCallback, useEffect, useState } from "react";
import { FocusContext, useFocusable } from "@noriginmedia/norigin-spatial-navigation";
import { ServerClient } from "../../api/serverClient";
import {
  ServerSyncError,
  serverSyncErrorKey,
  syncServerLibrary,
} from "../../data/serverSync";
import { settings } from "../../data/settings";
import { useNavigation } from "../../navigation/NavigationStack";
import { Button, TextField } from "../components/TextField";
import { discoverServers } from "../../api/serverDiscovery";
import { t } from "../../i18n";

/** Pairing replaces provider credential entry on webOS. */
export function AddPlaylistScreen() {
  const { replace } = useNavigation();
  const [address, setAddress] = useState("http://192.168.1.2:32145");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [discovering, setDiscovering] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { ref, focusKey, focusSelf } = useFocusable({ trackChildren: true });

  useEffect(() => focusSelf(), [focusSelf]);

  const discover = useCallback(async () => {
    setDiscovering(true);
    try {
      const servers = await discoverServers();
      const firstAddress = servers.flatMap((server) => server.addresses)[0];
      if (firstAddress) setAddress(firstAddress);
      else setError(t("tv.desktop.not_found"));
    } finally {
      setDiscovering(false);
    }
  }, []);

  const pair = useCallback(async () => {
    setBusy(true);
    setError(null);
    try {
      const client = await ServerClient.pair(address, code);
      const playlists = await syncServerLibrary(client);
      const first = playlists[0];
      if (!first) throw new Error(t("tv.desktop.empty_library"));
      settings.lastPlaylistId = first.id;
      replace({ name: "dashboard", playlist: first });
    } catch (reason) {
      setError(
        reason instanceof ServerSyncError
          ? t(serverSyncErrorKey(reason))
          : reason instanceof Error && reason.message !== "Pairing failed"
          ? reason.message
          : t("add_playlist.auth_failed"),
      );
    } finally {
      setBusy(false);
    }
  }, [address, code, replace]);

  return (
    <FocusContext.Provider value={focusKey}>
      <div ref={ref} className="screen form-screen">
        <h1 className="screen-title">{t("tv.desktop.connect_title")}</h1>
        <div className="playlist-form">
          <TextField label={t("add_playlist.server_url")} value={address} onChange={setAddress} placeholder="192.168.1.20:32145" />
          <TextField label={t("tv.desktop.pairing_code")} value={code} onChange={(value) => setCode(value.replace(/\D/g, "").slice(0, 6))} placeholder={t("tv.desktop.code_placeholder")} />
          {error && <p className="form-error">{error}</p>}
          <div className="form-actions">
            <Button label={discovering ? t("common.loading") : t("common.search")} onSelect={() => { if (!discovering) void discover(); }} />
            <Button primary label={busy ? t("common.loading") : t("tv.desktop.connect_title")} onSelect={() => { if (!busy && code.length === 6) void pair(); }} />
          </div>
        </div>
      </div>
    </FocusContext.Provider>
  );
}
