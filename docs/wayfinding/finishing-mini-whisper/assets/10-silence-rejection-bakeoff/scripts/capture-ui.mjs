#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { open } from '/Users/thurstonsand/.pi/agent/npm/node_modules/glimpseui/src/glimpse.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const args = Object.fromEntries(process.argv.slice(2).map((value, index, all) => value.startsWith('--') ? [value.slice(2), all[index + 1]] : null).filter(Boolean));
if (!args['built-in'] || !args['work-headset']) {
  console.error('usage: capture-ui.mjs --built-in AV_INDEX --work-headset AV_INDEX');
  process.exit(2);
}
const manifestPath = resolve(root, 'fixtures/local-manifest.json');
const allFixtures = JSON.parse(readFileSync(manifestPath));
const fixtures = args.device ? allFixtures.filter(fixture => fixture.device === args.device) : allFixtures;
if (fixtures.length === 0) {
  console.error(`no fixtures for device role ${args.device}`);
  process.exit(2);
}
const indexes = { 'built-in': args['built-in'], 'approved-work-headset': args['work-headset'] };
let index = 0;
let recording = false;

const shell = `
<style>
:root { color-scheme: light dark; --bg: light-dark(oklch(0.97 0.008 250), oklch(0.18 0.012 250)); --surface: light-dark(white, oklch(0.23 0.012 250)); --ink: light-dark(oklch(0.22 0.015 250), oklch(0.94 0.008 250)); --muted: light-dark(oklch(0.43 0.015 250), oklch(0.72 0.012 250)); --line: light-dark(oklch(0.86 0.01 250), oklch(0.34 0.015 250)); --accent: light-dark(oklch(0.55 0.17 250), oklch(0.72 0.15 245)); }
* { box-sizing: border-box } body { margin: 0; font: 15px/1.45 system-ui, sans-serif; background: var(--bg); color: var(--ink) }
main { min-height: 100vh; display: flex; flex-direction: column; padding: 28px 32px }
header { display: flex; align-items: baseline; justify-content: space-between; border-bottom: 1px solid var(--line); padding-bottom: 14px }
h1 { margin: 0; font-size: 18px } #progress { color: var(--muted); font-variant-numeric: tabular-nums }
#content { flex: 1; display: flex; flex-direction: column; justify-content: center; max-width: 68ch }
.meta { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 18px }.chip { border: 1px solid var(--line); border-radius: 999px; padding: 4px 9px; color: var(--muted); font-size: 13px }
h2 { margin: 0 0 12px; font-size: 26px; text-wrap: balance } #prompt { margin: 0; font-size: 19px; text-wrap: pretty }
#status { min-height: 28px; margin-top: 24px; color: var(--muted) } #status.live { color: oklch(0.64 0.2 25); font-weight: 650 }
footer { display: flex; justify-content: space-between; gap: 12px; border-top: 1px solid var(--line); padding-top: 16px }
.group { display: flex; gap: 10px } button { appearance: none; border: 1px solid var(--line); border-radius: 8px; padding: 10px 16px; background: var(--surface); color: var(--ink); font: inherit; font-weight: 600; cursor: pointer }
button:hover { border-color: var(--muted) } button:focus-visible { outline: 3px solid color-mix(in oklch, var(--accent) 35%, transparent); outline-offset: 2px }
button.primary { background: var(--accent); color: light-dark(white, oklch(0.16 0.02 250)); border-color: transparent } button:disabled { opacity: .45; cursor: default }
@media (prefers-reduced-motion: no-preference) { #status.live { animation: pulse 1.2s ease-in-out infinite } @keyframes pulse { 50% { opacity: .55 } } }
</style>
<main><header><h1>MiniWhisper · microphone corpus</h1><span id="progress"></span></header><div id="content"><div class="meta" id="meta"></div><h2 id="title"></h2><p id="prompt"></p><p id="status"></p></div><footer><div class="group"><button id="quit">Stop for now</button><button id="skip">Skip fixture</button></div><button class="primary" id="record">Record</button></footer></main>
<script>
const send = action => window.glimpse.send({ action });
document.getElementById('quit').addEventListener('click', () => send('quit'));
document.getElementById('skip').addEventListener('click', () => send('skip'));
document.getElementById('record').addEventListener('click', () => send('record'));
window.renderFixture = fixture => {
  document.getElementById('progress').textContent = fixture.progress;
  document.getElementById('meta').innerHTML = fixture.meta.map(item => '<span class="chip">' + item + '</span>').join('');
  document.getElementById('title').textContent = fixture.title;
  document.getElementById('prompt').textContent = fixture.prompt;
  document.getElementById('status').textContent = fixture.exists ? 'Already recorded. Keep it, or record again.' : 'Ready. Recording begins after a three-second count-in.';
  document.getElementById('status').className = '';
  document.getElementById('record').textContent = fixture.exists ? 'Record again' : 'Record';
  [...document.querySelectorAll('button')].forEach(button => button.disabled = false);
};
window.setStatus = (text, live = false) => { const el = document.getElementById('status'); el.textContent = text; el.className = live ? 'live' : ''; };
window.setBusy = busy => [...document.querySelectorAll('button')].forEach(button => button.disabled = busy);
</script>`;

const win = open(shell, { width: 700, height: 500, title: 'Silence rejection capture', floating: true, noDock: false });
const send = source => win.send(source);
const wait = milliseconds => new Promise(resolvePromise => setTimeout(resolvePromise, milliseconds));

function current() { return fixtures[index]; }
function pathFor(fixture) { return resolve(dirname(manifestPath), fixture.file); }
function render() {
  if (index >= fixtures.length) {
    send(`document.getElementById('content').innerHTML='<h2>Capture complete.</h2><p>Every available fixture has been visited. Close this window to continue with classification.</p>'; document.querySelector('footer').innerHTML='<button class="primary" onclick="window.glimpse.close()">Close</button>'; document.getElementById('progress').textContent='${fixtures.length} / ${fixtures.length}'`);
    return;
  }
  const fixture = current();
  send(`renderFixture(${JSON.stringify({ progress: `${index + 1} / ${fixtures.length}`, meta: [fixture.split, fixture.device, fixture.category, `${fixture.capture_seconds} seconds`], title: fixture.id, prompt: fixture.prompt, exists: existsSync(pathFor(fixture)) })})`);
}
async function record() {
  if (recording) return;
  recording = true;
  send('setBusy(true)');
  for (const count of [3, 2, 1]) { send(`setStatus('Recording in ${count}…', true)`); await wait(700); }
  const fixture = current();
  send(`setStatus('Recording · ${fixture.capture_seconds} seconds', true)`);
  const child = spawn(resolve(root, 'scripts/record.sh'), [indexes[fixture.device], String(fixture.capture_seconds), pathFor(fixture)], { stdio: ['ignore', 'pipe', 'pipe'] });
  let error = '';
  child.stderr.on('data', chunk => error += chunk);
  const code = await new Promise(resolvePromise => child.on('close', resolvePromise));
  recording = false;
  if (code !== 0) {
    send(`setStatus(${JSON.stringify(`Capture failed: ${error.trim()}`)}); setBusy(false)`);
    return;
  }
  send("setStatus('Recorded. Moving to the next fixture…')");
  await wait(550);
  index += 1;
  render();
}

win.on('ready', render);
win.on('message', async message => {
  if (message.action === 'record') await record();
  if (message.action === 'skip' && !recording) { index += 1; render(); }
  if (message.action === 'quit' && !recording) win.close();
});
win.on('closed', () => process.exit(0));
