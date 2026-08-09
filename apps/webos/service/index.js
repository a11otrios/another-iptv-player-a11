"use strict";

const dgram = require("dgram");
const Service = require("webos-service");
const service = new Service("com.devyorg.anotheriptvplayer.discovery");

service.register("discover", (message) => {
  const socket = dgram.createSocket({ type: "udp4", reuseAddr: true });
  const found = new Map();
  const timeoutMs = Math.max(500, Math.min(Number(message.payload.timeoutMs) || 1800, 5000));
  let finished = false;

  const finish = () => {
    if (finished) return;
    finished = true;
    try { socket.close(); } catch (_) {}
    message.respond({ returnValue: true, servers: Array.from(found.values()) });
  };

  socket.on("message", (buffer) => {
    try {
      const server = JSON.parse(buffer.toString("utf8"));
      if (server.protocol !== "AIPTV_DISCOVER_V1" || !Array.isArray(server.addresses)) return;
      found.set(`${server.serverName}:${server.port}`, server);
    } catch (_) {}
  });
  socket.on("error", finish);
  socket.bind(0, "0.0.0.0", () => {
    socket.setBroadcast(true);
    const probe = Buffer.from("AIPTV_DISCOVER_V1", "utf8");
    socket.send(probe, 0, probe.length, 32146, "255.255.255.255");
  });
  setTimeout(finish, timeoutMs);
});
