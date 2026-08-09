const SERVICE_URI = "luna://com.devyorg.anotheriptvplayer.discovery";

export interface DiscoveredServer {
  name: string;
  serverName: string;
  addresses: string[];
}

export function discoverServers(): Promise<DiscoveredServer[]> {
  const request = window.webOS?.service?.request;
  if (!request) return Promise.resolve([]);
  return new Promise((resolve) => {
    let settled = false;
    const finish = (servers: DiscoveredServer[]) => {
      if (settled) return;
      settled = true;
      resolve(servers);
    };
    const timer = window.setTimeout(() => finish([]), 3500);
    request(SERVICE_URI, {
      method: "discover",
      parameters: { timeoutMs: 1800 },
      onSuccess: (response) => {
        window.clearTimeout(timer);
        const value = response as { servers?: DiscoveredServer[] };
        finish(Array.isArray(value.servers) ? value.servers : []);
      },
      onFailure: () => {
        window.clearTimeout(timer);
        finish([]);
      },
    });
  });
}
