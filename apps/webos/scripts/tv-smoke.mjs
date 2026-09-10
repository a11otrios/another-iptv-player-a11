import { existsSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const APP_ID = 'com.devyorg.anotheriptvplayer';
const IPK_NAME = `${APP_ID}_1.7.17_all.ipk`;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cliDir = path.join(root, 'node_modules', '@webos-tools', 'cli', 'bin');
const device = readOption('--device') ?? 'tv';
const ipk = path.resolve(root, readOption('--ipk') ?? IPK_NAME);

if (process.argv.includes('--help')) {
  console.log('Usage: npm run tv:smoke -- [--device tv] [--ipk path-to-package.ipk]');
  process.exit(0);
}

if (!existsSync(ipk)) {
  fail(`Package not found: ${ipk}\nRun \"npm run package\" first.`);
}

// Device listings can include the stored key-server passphrase. Inspect the
// captured output for the target name without copying credentials to logs.
const devices = run('ares-setup-device.js', ['--list'], { capture: true, echo: false });
const configured = devices
  .split(/\r?\n/)
  .some((line) => line.trim().startsWith(`${device} `) || line.trim().startsWith(`${device}\t`));

if (!configured) {
  fail(
    `No webOS device named \"${device}\" is configured.\n` +
      `Add the TV with \"ares-setup-device --add ${device}\", then rerun this command.`,
  );
}

console.log(`[1/4] Checking ${device} connectivity...`);
run('ares-device.js', ['--system-info', '--device', device]);

console.log(`[2/4] Installing ${path.basename(ipk)}...`);
run('ares-install.js', ['--device', device, ipk]);

console.log(`[3/4] Verifying ${APP_ID}...`);
const installed = run('ares-install.js', ['--device', device, '--list'], { capture: true });
if (!installed.split(/\r?\n/).some((line) => line.trim() === APP_ID)) {
  fail(`The install command completed, but ${APP_ID} was not found on ${device}.`);
}

console.log(`[4/4] Launching ${APP_ID}...`);
run('ares-launch.js', ['--device', device, APP_ID]);
console.log(`LG smoke deploy completed successfully on ${device}.`);

function readOption(name) {
  const index = process.argv.indexOf(name);
  if (index === -1) return undefined;
  const value = process.argv[index + 1];
  if (!value || value.startsWith('--')) fail(`Missing value for ${name}.`);
  return value;
}

function run(script, args, { capture = false, echo = true } = {}) {
  const result = spawnSync(process.execPath, [path.join(cliDir, script), ...args], {
    cwd: root,
    encoding: 'utf8',
    stdio: capture ? ['inherit', 'pipe', 'pipe'] : 'inherit',
  });

  if (capture && echo) {
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
  }

  if (result.error) fail(`${script} could not start: ${result.error.message}`);
  if (result.status !== 0) fail(`${script} exited with code ${result.status ?? 'unknown'}.`);
  return result.stdout ?? '';
}

function fail(message) {
  console.error(`\nTV smoke test failed: ${message}`);
  process.exit(1);
}
