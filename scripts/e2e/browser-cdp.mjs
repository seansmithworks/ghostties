// End-to-end assertions for `gt browser open` and the CDP gateway.
// Driven by scripts/e2e-browser-cdp.sh, which launches the capture build and
// passes the context in through E2E_* environment variables. Each check
// prints a "PASS:" line with the evidence; the first failure throws.
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import http from 'node:http';
import path from 'node:path';

const env = (name) => {
  const v = process.env[name];
  if (!v) throw new Error(`missing ${name}`);
  return v;
};
const APP_PID = Number(env('E2E_APP_PID'));
const STATE_DIR = env('E2E_STATE_DIR');
const OUT = env('E2E_OUT');
const GT = env('E2E_GT');
const TERMINAL = env('E2E_TERMINAL');
const NODE_DIR = env('E2E_NODE_DIR');

const require = createRequire(path.join(NODE_DIR, 'x.js'));
const { chromium } = require('playwright-core');

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const pass = (what, evidence = '') => console.log(`PASS: ${what}${evidence ? ` -- ${evidence}` : ''}`);
function assert(cond, what) {
  if (!cond) throw new Error(`FAIL: ${what}`);
}
const alive = () => {
  try {
    process.kill(APP_PID, 0);
    return true;
  } catch {
    return false;
  }
};

// ---- fixture page ----------------------------------------------------------

const page = http.createServer((_, res) => {
  res.setHeader('content-type', 'text/html');
  res.end('<!doctype html><title>e2e</title><body style="font:32px sans-serif"><h1>ghostties e2e</h1></body>');
});
await new Promise((r) => page.listen(0, '127.0.0.1', r));
const PAGE_URL = `http://127.0.0.1:${page.address().port}/`;

// ---- gateway context --------------------------------------------------------

const cdp = JSON.parse(readFileSync(path.join(STATE_DIR, 'cdp.json'), 'utf8'));
assert(cdp.pid === APP_PID, `cdp.json pid ${cdp.pid} is not the launched app ${APP_PID}`);
const gtEnv = {
  ...process.env,
  GHOSTTIES_CDP_ENDPOINT: cdp.endpoint,
  GHOSTTIES_BROWSER_TOKEN: cdp.token,
  GHOSTTIES_SESSION_ID: TERMINAL,
};

function gtOpen(url) {
  return spawnSync(GT, ['browser', 'open', url], { env: gtEnv, encoding: 'utf8', timeout: 30000 });
}

/** `gt browser open`, retrying while the fixture terminal is still starting. */
async function gtOpenWhenReady(url) {
  const deadline = Date.now() + 60000;
  for (;;) {
    const r = gtOpen(url);
    if (r.status === 0) return JSON.parse(r.stdout);
    if (!/no such terminal session/.test(r.stderr) || Date.now() > deadline) {
      throw new Error(`gt browser open failed (${r.status}): ${r.stderr}`);
    }
    await sleep(1000);
  }
}

/** Window count for the app, from the window server (no accessibility). */
function appWindows() {
  const swift = `
import CoreGraphics
let pid = Int32(CommandLine.arguments[1])!
let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let mine = all.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
print(mine.count)`;
  const r = spawnSync('swift', ['-', String(APP_PID)], { input: swift, encoding: 'utf8', timeout: 60000 });
  return Number(r.stdout.trim());
}

async function jsonList() {
  const res = await fetch(`${cdp.endpoint}/json/list`);
  const body = await res.text();
  assert(res.status === 200, `/json/list answered ${res.status}: ${body}`);
  return JSON.parse(body);
}

/** One raw CDP request over a WebSocket, resolving with the reply. */
function rawCdp(wsUrl, method, params = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const id = 1;
    const timer = setTimeout(() => reject(new Error(`no reply to ${method}`)), 15000);
    ws.onopen = () => ws.send(JSON.stringify({ id, method, params }));
    ws.onmessage = (e) => {
      const msg = JSON.parse(String(e.data));
      if (msg.id === id) {
        clearTimeout(timer);
        ws.close();
        resolve(msg);
      }
    };
    ws.onerror = () => {
      clearTimeout(timer);
      reject(new Error(`websocket error talking to ${wsUrl}`));
    };
  });
}

function pngWidth(buf) {
  assert(buf.subarray(1, 4).toString() === 'PNG', 'screenshot is not a PNG');
  return buf.readUInt32BE(16);
}

// The target id itself is checked against /json/list; Playwright's own
// newCDPSession needs Target.attachToBrowserTarget, which the gateway denies,
// so the page is found by the URL `gt browser open` was given.
async function pageForTarget(browser, targetId) {
  for (let i = 0; i < 30; i++) {
    for (const ctx of browser.contexts()) {
      const p = ctx.pages().find((candidate) => candidate.url() === PAGE_URL);
      if (p) return p;
    }
    await sleep(500);
  }
  throw new Error(`Playwright never saw the page for target ${targetId}`);
}

// ---- 0. outside a Ghostties terminal, gt refuses ----------------------------

const bare = spawnSync(GT, ['browser', 'open', PAGE_URL], {
  env: { PATH: process.env.PATH },
  encoding: 'utf8',
});
assert(bare.status !== 0 && /needs a Ghostties Dev terminal/.test(bare.stderr), 'gt without the environment must refuse');
pass('gt browser open outside a Ghostties terminal exits non-zero', bare.stderr.trim());

// ---- 1. gt browser open ------------------------------------------------------

const opened = await gtOpenWhenReady(PAGE_URL);
assert(opened.endpoint && opened.targetId && opened.wsUrl, `incomplete reply: ${JSON.stringify(opened)}`);
assert(opened.endpoint === cdp.endpoint, 'endpoint differs from cdp.json');
assert(opened.wsUrl.endsWith(`/devtools/page/${opened.targetId}`), 'wsUrl does not name the target');
pass('gt browser open returned {endpoint,targetId,wsUrl}', JSON.stringify(opened));

const listed = await jsonList();
assert(listed.some((t) => t.id === opened.targetId), 'targetId missing from /json/list');
const listedSelf = listed.find((t) => t.id === opened.targetId);
assert(listedSelf.webSocketDebuggerUrl === opened.wsUrl, `/json/list says ${listedSelf.webSocketDebuggerUrl}, gt said ${opened.wsUrl}`);
pass('/json/list through the gateway lists the target', `${listed.length} target(s)`);

// ---- 2. Playwright attaches and screenshots ----------------------------------

const browser = await chromium.connectOverCDP(opened.endpoint);
const pwPage = await pageForTarget(browser, opened.targetId);
const shot = await pwPage.screenshot({ path: path.join(OUT, 'playwright.png') });
const width = pngWidth(shot);
assert(width > 0, 'screenshot width is 0');
pass('Playwright connectOverCDP attached and screenshotted', `${await pwPage.title()} width=${width}px -> ${path.join(OUT, 'playwright.png')}`);

// ---- 3. Browser.close is refused ---------------------------------------------

const version = await (await fetch(`${opened.endpoint}/json/version`)).json();
assert(new URL(version.webSocketDebuggerUrl).port !== '0', `unroutable ws url ${version.webSocketDebuggerUrl}`);
const windowsBeforeClose = appWindows();
const closeReply = await rawCdp(version.webSocketDebuggerUrl, 'Browser.close');
assert(closeReply.error && /not allowed/.test(closeReply.error.message), `Browser.close was not refused: ${JSON.stringify(closeReply)}`);
await sleep(3000);
assert(alive(), 'the app died after Browser.close');
const windowsAfterClose = appWindows();
assert(windowsAfterClose === windowsBeforeClose, `the app's window count changed (${windowsBeforeClose} -> ${windowsAfterClose}): a Quit alert?`);
pass('Browser.close returned an error and the app is alive 3s later', `${JSON.stringify(closeReply.error)}; app windows ${windowsBeforeClose} -> ${windowsAfterClose}`);

// ---- 4. Target.createTarget is denied -----------------------------------------

const before = (await jsonList()).length;
const createReply = await rawCdp(version.webSocketDebuggerUrl, 'Target.createTarget', { url: 'about:blank' });
assert(createReply.error && /gt browser open/.test(createReply.error.message), `createTarget was not denied: ${JSON.stringify(createReply)}`);
assert((await jsonList()).length === before, 'createTarget added a target anyway');
const viaHttp = await fetch(`${opened.endpoint}/json/new?about:blank`, { method: 'PUT' });
assert(viaHttp.status === 403, `/json/new answered ${viaHttp.status}, not 403`);
pass('Target.createTarget and /json/new are denied', JSON.stringify(createReply.error));

// ---- 5. Target.closeTarget removes the session --------------------------------

const closeTarget = await rawCdp(version.webSocketDebuggerUrl, 'Target.closeTarget', { targetId: opened.targetId });
assert(closeTarget.result && closeTarget.result.success !== false, `closeTarget failed: ${JSON.stringify(closeTarget)}`);
let gone = false;
for (let i = 0; i < 40 && !gone; i++) {
  gone = !(await jsonList()).some((t) => t.id === opened.targetId);
  if (!gone) await sleep(250);
}
assert(gone, 'the target is still in /json/list after closeTarget');
let sessionClosed = false;
for (let i = 0; i < 40 && !sessionClosed; i++) {
  sessionClosed = /\[BrowserAgent\] closed browser session /.test(readFileSync(path.join(OUT, 'app.log'), 'utf8'));
  if (!sessionClosed) await sleep(250);
}
assert(sessionClosed, 'the app never logged the browser session closing');
assert(alive(), 'the app died after closeTarget');
pass('Target.closeTarget removed the target and its session; app alive', JSON.stringify(closeTarget.result));

await browser.close().catch(() => {});

// ---- 6. Playwright browser.close() does not quit the app ------------------------

const second = await gtOpenWhenReady(PAGE_URL);
assert(second.targetId !== opened.targetId, 'a closed browser was reused instead of opening a fresh one');
pass('after the close, gt browser open makes a fresh browser', second.targetId);

const browser2 = await chromium.connectOverCDP(second.endpoint);
await pageForTarget(browser2, second.targetId);
await browser2.close();
await sleep(3000);
assert(alive(), 'the app quit after Playwright browser.close()');
assert((await jsonList()).some((t) => t.id === second.targetId), 'the page vanished after Playwright disconnected');
pass('Playwright browser.close() disconnected; app alive and the page is still there');

page.close();
writeFileSync(path.join(OUT, 'result.json'), JSON.stringify({ ok: true, opened, second }, null, 2));
