import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const dist = resolve("dist");
const service = resolve("service");
if (!existsSync(resolve(dist, "appinfo.json"))) {
  throw new Error("dist/appinfo.json is missing; run the webOS build first");
}

const cli = fileURLToPath(new URL("../node_modules/@webos-tools/cli/bin/ares-package.js", import.meta.url));
// Vite already minifies both modern and legacy bundles. LG's older minifier
// cannot parse every construct in the modern chunk, so package without a
// redundant second minification pass.
const result = spawnSync(process.execPath, [cli, "--no-minify", dist, service, "-o", resolve(".")], {
  stdio: "inherit",
  shell: false,
});
if (result.error) {
  throw new Error("The local webOS CLI could not be started. Run pnpm install, then try again.");
}
process.exitCode = result.status ?? 1;
