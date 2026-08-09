export function isWebOS(): boolean {
  return typeof window !== "undefined" && (typeof window.webOS !== "undefined" || /Web0S|webOS/i.test(navigator.userAgent));
}

export function exitApp(): void {
  if (isWebOS()) {
    if (window.webOS?.platformBack) window.webOS.platformBack();
    else window.close();
  } else {
    console.info("[platform] exitApp() ignored outside webOS");
  }
}

export function openExternalUrl(url: string): Promise<void> {
  if (!isWebOS() || !window.webOS?.service?.request) {
    window.open(url, "_blank", "noopener,noreferrer");
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    window.webOS!.service!.request("luna://com.webos.applicationManager", {
      method: "launch",
      parameters: {
        id: "com.webos.app.browser",
        params: { target: url },
      },
      onSuccess: () => resolve(),
      onFailure: (error) => reject(new Error(`Could not open browser: ${String(error)}`)),
    });
  });
}
