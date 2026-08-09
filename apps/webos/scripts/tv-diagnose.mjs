import { writeFile } from "node:fs/promises";
import path from "node:path";

const host = readOption("--host") ?? "192.168.1.168";
const appId = readOption("--app") ?? "com.devyorg.anotheriptvplayer";
const output = path.resolve(readOption("--screenshot") ?? "tv-screenshot.png");
const pages = await fetch(`http://${host}:9998/json`).then((response) => response.json());
const page = pages.find((entry) => entry.url?.includes(`/applications/${appId}/`));
if (!page?.webSocketDebuggerUrl) throw new Error(`${appId} is not inspectable on ${host}`);

const socket = new WebSocket(page.webSocketDebuggerUrl);
const pending = new Map();
let nextId = 1;
const diagnosticEvents = [];
const networkRequests = new Map();

socket.addEventListener("message", (event) => {
  const message = JSON.parse(event.data);
  if (message.id) {
    const request = pending.get(message.id);
    if (request) {
      pending.delete(message.id);
      message.error ? request.reject(new Error(message.error.message)) : request.resolve(message.result);
    }
    return;
  }
  if (message.method === "Runtime.exceptionThrown" || message.method === "Runtime.consoleAPICalled") {
    const safeMessage = JSON.parse(JSON.stringify(message));
    diagnosticEvents.push(safeMessage);
  }
  if (message.method === "Network.requestWillBeSent") {
    const request = message.params.request;
    networkRequests.set(message.params.requestId, {
      requestId: message.params.requestId,
      url: request.url,
      method: request.method,
      startedAt: message.params.timestamp,
    });
  }
  if (message.method === "Network.responseReceived") {
    const request = networkRequests.get(message.params.requestId);
    if (request) {
      request.status = message.params.response.status;
      request.headersAt = message.params.timestamp;
    }
  }
  if (message.method === "Network.loadingFinished") {
    const request = networkRequests.get(message.params.requestId);
    if (request) {
      request.finishedAt = message.params.timestamp;
      request.bytes = message.params.encodedDataLength;
    }
  }
  if (message.method === "Network.loadingFailed") {
    const request = networkRequests.get(message.params.requestId);
    if (request) request.error = message.params.errorText;
  }
});

await new Promise((resolve, reject) => {
  socket.addEventListener("open", resolve, { once: true });
  socket.addEventListener("error", reject, { once: true });
});

await command("Runtime.enable");
await command("Page.enable");
await command("Network.enable");
const requestedShortcutPage = readOption("--shortcut-page");
const summaryOnly = process.argv.includes("--summary-only");
let requestedShortcutDescriptors = [];
if (requestedShortcutPage) {
  const shortcutResult = await command("Runtime.evaluate", {
    expression: `(async function () {
      var stored = localStorage.getItem("aiptv.webos.server.v1");
      if (!stored) return "[]";
      var connection = JSON.parse(stored);
      var url = connection.baseUrl + "/shortcuts?playlistId=" +
        encodeURIComponent(${JSON.stringify(readOption("--playlist-id") ?? "")}) +
        "&page=" + encodeURIComponent(${JSON.stringify(requestedShortcutPage)});
      var response = await fetch(url, {
        headers: { Authorization: "Bearer " + connection.token },
      });
      var envelope = await response.json();
      var shortcuts = envelope && envelope.data || {};
      return JSON.stringify(Object.keys(shortcuts).map(function (number) {
        return { number: number, name: shortcuts[number].name || "" };
      }));
    }())`,
    awaitPromise: true,
    returnByValue: true,
  });
  const shortcutValue = shortcutResult.result.value;
  requestedShortcutDescriptors = typeof shortcutValue === "string"
    ? JSON.parse(shortcutValue || "[]")
    : Array.isArray(shortcutValue)
      ? shortcutValue
      : [];
}
if (process.argv.includes("--shortcuts-only")) {
  console.log(JSON.stringify({ requestedShortcutDescriptors }, null, 2));
  socket.close();
  process.exit(0);
}
if (process.argv.includes("--reload")) {
  await command("Page.reload", { ignoreCache: true });
  await new Promise((resolve) => setTimeout(resolve, 3000));
}
const keySequence = readOption("--keys")?.split(",").filter(Boolean) ?? [];
if (process.argv.includes("--enter")) keySequence.push("Enter");
for (const keyName of keySequence) {
  await dispatchKey(keyName);
  await new Promise((resolve) => setTimeout(resolve, 350));
}
const textInput = readOption("--text");
if (textInput) {
  await command("Runtime.evaluate", {
    expression: `(function () { var input = document.querySelector("input[data-focused=true], [data-focused=true] input, input:focus"); if (input) input.focus(); return !!input; }())`,
    returnByValue: true,
  });
  for (const character of textInput) {
    await command("Input.dispatchKeyEvent", {
      type: "char",
      key: character,
      text: character,
      unmodifiedText: character,
    });
  }
}
const videoErrorCount = Number(
  readOption("--video-errors") ?? (process.argv.includes("--video-error") ? "1" : "0"),
);
for (let index = 0; index < videoErrorCount; index += 1) {
  const dispatched = await command("Runtime.evaluate", {
    expression: `(function () {
      var video = document.querySelector("video");
      if (!video) return false;
      video.dispatchEvent(new Event("error"));
      return true;
    }())`,
    returnByValue: true,
  });
  if (!dispatched.result.value) throw new Error("No video element is mounted");
  if (index + 1 < videoErrorCount) {
    await new Promise((resolve) => setTimeout(
      resolve,
      Number(readOption("--video-error-delay") ?? 12000),
    ));
  }
}
await new Promise((resolve) => setTimeout(resolve, Number(readOption("--wait") ?? 2000)));
const playbackDescriptors = [];
const shortcutDescriptors = [];
for (const request of networkRequests.values()) {
  if (request.url.includes("/api/v1/shortcuts?") && request.status === 200 && request.finishedAt) {
    try {
      const response = await command("Network.getResponseBody", { requestId: request.requestId });
      const envelope = JSON.parse(response.body);
      const shortcuts = envelope?.data;
      if (shortcuts && typeof shortcuts === "object") {
        shortcutDescriptors.push(...Object.entries(shortcuts).map(([number, shortcut]) => ({
          number,
          name: shortcut?.name ?? "",
        })));
      }
    } catch {}
  }
  if (!request.url.endsWith("/api/v1/playback") || request.status !== 200 || !request.finishedAt) continue;
  try {
    const response = await command("Network.getResponseBody", { requestId: request.requestId });
    const envelope = JSON.parse(response.body);
    const descriptor = envelope?.data;
    if (descriptor) {
      playbackDescriptors.push({
        mode: descriptor.mode,
        mimeType: descriptor.mimeType,
        isLive: descriptor.isLive,
        startPositionMs: descriptor.startPositionMs,
      });
    }
  } catch {}
}
const evaluated = await command("Runtime.evaluate", {
  expression: `(function () {
    var root = document.getElementById("root");
    var video = document.querySelector("video");
    var mediaSource = video && video.querySelector("source");
    var subtitleOverlay = document.querySelector(".subtitle-overlay");
    function redactedMediaUrl(value) {
      if (!value) return "";
      var link = document.createElement("a");
      link.href = value;
      return link.origin + link.pathname + (link.search ? "?<redacted>" : "");
    }
    function redactedMediaPath(value) {
      if (!value) return "";
      var link = document.createElement("a");
      link.href = value;
      return link.origin + link.pathname;
    }
    return JSON.stringify({
      title: document.title,
      readyState: document.readyState,
      userAgent: navigator.userAgent,
      bodyText: ${summaryOnly} ? "" : (document.body && document.body.innerText || "").slice(0, 2000),
      rootChildren: root ? root.childElementCount : -1,
      rootHtml: ${summaryOnly} ? "" : (root && root.innerHTML || "").slice(0, 2000),
      focusedText: (document.querySelector("[data-focused=true]") || {}).innerText || "",
      focusedKey: (document.querySelector("[data-focused=true]") || {}).getAttribute &&
        document.querySelector("[data-focused=true]").getAttribute("data-fk") || "",
      shortcutPage: (document.querySelector(".shortcut-page-tab.active") || {}).innerText || "",
      gridCards: document.querySelectorAll(".grid-wrap > *").length,
      posterImages: Array.prototype.reduce.call(
        document.querySelectorAll(".poster-image"),
        function (summary, poster) {
          var state = poster.getAttribute("data-image-state") || "unknown";
          var source = poster.getAttribute("data-image-source") || "unknown";
          summary.total += 1;
          summary.states[state] = (summary.states[state] || 0) + 1;
          summary.sources[source] = (summary.sources[source] || 0) + 1;
          return summary;
        },
        { total: 0, states: {}, sources: {} },
      ),
      visibleScreen: (document.querySelector(".screen-layer[style*=flex] .screen") || {}).className || "",
      playerControls: Array.prototype.map.call(
        document.querySelectorAll(".player-play-button, .player-chrome-button, .player-seek"),
        function (control) {
          return {
            className: control.className,
            text: (control.innerText || "").trim(),
            focused: control.getAttribute("data-focused") || "",
            visible: !!(control.offsetWidth || control.offsetHeight || control.getClientRects().length),
          };
        },
      ),
      subtitleOverlay: subtitleOverlay ? {
        text: (subtitleOverlay.innerText || "").trim(),
        visible: !!(subtitleOverlay.offsetWidth || subtitleOverlay.offsetHeight || subtitleOverlay.getClientRects().length),
      } : null,
      video: video ? {
        src: redactedMediaUrl(video.getAttribute("src") || ""),
        currentSrc: redactedMediaUrl(video.currentSrc || ""),
        readyState: video.readyState,
        networkState: video.networkState,
        paused: video.paused,
        currentTime: video.currentTime,
        duration: video.duration,
        objectFit: video.style.objectFit || "",
        error: video.error ? { code: video.error.code, message: video.error.message || "" } : null,
        textTracks: Array.prototype.map.call(video.textTracks || [], function (track) {
          return {
            label: track.label || "",
            language: track.language || "",
            mode: track.mode || "",
            cueCount: track.cues ? track.cues.length : 0,
            activeCue: track.activeCues && track.activeCues.length
              ? track.activeCues[0].text || ""
              : "",
          };
        }),
        source: mediaSource ? {
          path: redactedMediaPath(mediaSource.src),
          type: mediaSource.type || "",
          canPlayType: mediaSource.type ? video.canPlayType(mediaSource.type) : "",
        } : null,
      } : null,
      scripts: Array.prototype.map.call(document.scripts, function (script) {
        return { src: script.src, type: script.type, noModule: script.noModule };
      }),
    });
  }())`,
  returnByValue: true,
});
const screenshot = await command("Page.captureScreenshot", { format: "png" });
await writeFile(output, Buffer.from(screenshot.data, "base64"));

console.log(JSON.stringify({
  page: { title: page.title, url: page.url },
  document: JSON.parse(evaluated.result.value),
  diagnosticEvents,
  apiRequests: Array.from(networkRequests.values())
    .filter((request) => request.url.includes("/api/v1/"))
    .map((request) => ({ ...request, url: redactNetworkUrl(request.url) })),
  playbackDescriptors,
  shortcutDescriptors,
  requestedShortcutDescriptors,
  mediaRequestCount: Array.from(networkRequests.values()).filter((request) => !request.url.includes("/api/v1/")).length,
  screenshot: output,
}, null, 2));
socket.close();

function command(method, params = {}) {
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
}

async function dispatchKey(keyName) {
  const keys = {
    0: { code: "Digit0", keyCode: 48 },
    1: { code: "Digit1", keyCode: 49 },
    2: { code: "Digit2", keyCode: 50 },
    3: { code: "Digit3", keyCode: 51 },
    4: { code: "Digit4", keyCode: 52 },
    5: { code: "Digit5", keyCode: 53 },
    6: { code: "Digit6", keyCode: 54 },
    7: { code: "Digit7", keyCode: 55 },
    8: { code: "Digit8", keyCode: 56 },
    9: { code: "Digit9", keyCode: 57 },
    Enter: { code: "Enter", keyCode: 13 },
    ArrowUp: { code: "ArrowUp", keyCode: 38 },
    ArrowDown: { code: "ArrowDown", keyCode: 40 },
    ArrowLeft: { code: "ArrowLeft", keyCode: 37 },
    ArrowRight: { code: "ArrowRight", keyCode: 39 },
    Escape: { code: "Escape", keyCode: 27 },
    Back: { code: "BrowserBack", keyCode: 461 },
    Red: { code: "ColorF0Red", keyCode: 403 },
    Green: { code: "ColorF1Green", keyCode: 404 },
    Yellow: { code: "ColorF2Yellow", keyCode: 405 },
    Blue: { code: "ColorF3Blue", keyCode: 406 },
    ChannelUp: { code: "ChannelUp", keyCode: 427 },
    ChannelDown: { code: "ChannelDown", keyCode: 428 },
    PlayPause: { code: "MediaPlayPause", keyCode: 10252 },
  };
  const definition = keys[keyName];
  if (!definition) throw new Error(`Unsupported key: ${keyName}`);
  const params = {
    key: keyName,
    code: definition.code,
    windowsVirtualKeyCode: definition.keyCode,
    nativeVirtualKeyCode: definition.keyCode,
  };
  await command("Input.dispatchKeyEvent", { type: "keyDown", ...params });
  await command("Input.dispatchKeyEvent", { type: "keyUp", ...params });
}

function readOption(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 ? process.argv[index + 1] : undefined;
}

function redactNetworkUrl(value) {
  try {
    const url = new URL(value);
    if (url.searchParams.has("access_token")) {
      url.searchParams.set("access_token", "<redacted>");
    }
    return url.toString();
  } catch {
    return value.replace(/access_token=[^&\s]+/gi, "access_token=<redacted>");
  }
}
