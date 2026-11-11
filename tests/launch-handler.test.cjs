// SPDX-License-Identifier: MPL-2.0
// Exercises the actual complete default command-line handler from the candidate,
// with browser services mocked. No browser profile or installation is modified.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { spawnSync } = require('node:child_process');
const { test } = require('node:test');

const handlerPath = process.env.ZEN_HANDLER_PATH || path.join(
  __dirname, '..', '.work', 'handler-fixture', 'BrowserContentHandler.patched.sys.mjs'
);
if (!process.env.ZEN_HANDLER_PATH) {
  const result = spawnSync(process.env.ZEN_POWERSHELL || 'powershell.exe', [
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
    path.join(__dirname, 'prepare-handler-fixture.ps1'), '-OutputPath', handlerPath,
  ], { encoding: 'utf8' });
  assert.equal(result.status, 0, `Could not prepare synthetic patched handler: ${result.error || result.stderr || result.stdout}`);
}
const source = fs.readFileSync(handlerPath, 'utf8');
const start = source.indexOf('function dch_handle(cmdLine) {');
const suffix = source.slice(start).match(/,\s*helpInfo:\s*""\s*,?\s*};\s*$/);
assert.ok(start >= 0 && suffix, 'Cannot locate the complete default command-line handler');
const handlerFunction = source.slice(start, start + suffix.index).trimEnd();

function browserWindow({ minimized = false } = {}) {
  const actions = [];
  return {
    actions,
    STATE_MINIMIZED: 2,
    windowState: minimized ? 2 : 1,
    restore() { actions.push('restore'); this.windowState = 1; },
    focus() { actions.push('focus'); },
  };
}

function run({
  args = [], initial = false, window = null, prevented = false,
  kiosk = false, enabled = true, permanentPrivate = false,
} = {}) {
  const calls = { windows: [], routed: [], lookups: [], prefs: [], errors: [] };
  const remaining = [...args];
  const commandLine = {
    state: initial ? 0 : 1,
    preventDefault: prevented,
    get length() { return remaining.length; },
    getArgument(index) { return remaining[index]; },
    findFlag(name) {
      return remaining.findIndex(arg => arg.replace(/^-{1,2}/, '') === name);
    },
    handleFlag(name) {
      const index = this.findFlag(name);
      if (index < 0) return false;
      remaining.splice(index, 1);
      return true;
    },
    handleFlagWithParam(name) {
      const index = this.findFlag(name);
      if (index < 0) return null;
      if (index + 1 >= remaining.length) throw new Error(`Missing parameter: ${name}`);
      return remaining.splice(index, 2)[1];
    },
  };
  const principal = { kind: 'system-principal' };
  const globals = {
    AppConstants: { platform: 'win' },
    Ci: {
      nsICommandLine: { STATE_INITIAL_LAUNCH: 0 },
      nsIBrowserDOMWindow: { OPEN_DEFAULTWINDOW: 0 },
    },
    gKiosk: kiosk,
    Services: {
      startup: { wasSilentlyStarted: false },
      wm: { getMostRecentWindow() { return null; } },
      prefs: {
        getBoolPref(name, fallback) {
          calls.prefs.push([name, fallback]);
          assert.equal(name, 'zen.window-reuse-on-launch');
          return enabled;
        },
      },
    },
    lazy: {
      gSystemPrincipal: principal,
      PrivateBrowsingUtils: { permanentPrivateBrowsing: permanentPrivate },
      WindowsUIUtils: { inWin10TabletMode: false },
      BrowserWindowTracker: {
        getTopWindow(options) { calls.lookups.push(options); return window; },
      },
    },
    resolveURIInternal(command, value) {
      return { uri: { spec: value }, principal };
    },
    shouldLoadURI() { return true; },
    handURIToExistingBrowser(...values) { calls.routed.push(values); },
    openBrowserWindow(...values) { calls.windows.push(values); },
    maybeRecordSearchActivationTelemetry() {},
    maybeRecordToHandleTelemetry() {},
    console: { error(...values) { calls.errors.push(values); } },
  };
  const handler = vm.runInNewContext(`(${handlerFunction})`, globals, {
    filename: handlerPath,
  });
  handler.call({ _haveProfile: true, handleNotification() { return false; } }, commandLine);
  return { calls, commandLine, principal };
}

test('cold launch preserves opening the initial browser window', () => {
  const existing = browserWindow();
  const { calls } = run({ initial: true, window: existing });
  assert.equal(calls.windows.length, 1);
  assert.equal(calls.lookups.length, 0);
  assert.deepEqual(existing.actions, []);
});

test('argument-free relaunch focuses an existing main window without opening one', () => {
  const existing = browserWindow();
  const { calls } = run({ window: existing });
  assert.equal(calls.windows.length, 0);
  assert.deepEqual(existing.actions, ['focus']);
  assert.equal(calls.lookups.length, 1);
  assert.equal(calls.lookups[0].allowFromInactiveWorkspace, true);
  assert.equal(calls.lookups[0].private, false);
});

test('a minimized main window is restored before focus', () => {
  const existing = browserWindow({ minimized: true });
  const { calls } = run({ window: existing });
  assert.equal(calls.windows.length, 0);
  assert.deepEqual(existing.actions, ['restore', 'focus']);
});

test('absence of a normal main window preserves the ordinary new-window fallback', () => {
  const { calls } = run();
  assert.equal(calls.lookups.length, 1);
  assert.equal(calls.lookups[0].private, false);
  assert.equal(calls.windows.length, 1);
});

test('permanent private browsing searches for a private window', () => {
  const existing = browserWindow();
  const { calls } = run({ permanentPrivate: true, window: existing });
  assert.equal(calls.lookups[0].private, true);
  assert.equal(calls.windows.length, 0);
  assert.deepEqual(existing.actions, ['focus']);
});

test('kiosk launch retains opening a window', () => {
  const existing = browserWindow();
  const { calls } = run({ kiosk: true, window: existing });
  assert.equal(calls.windows.length, 1);
  assert.equal(calls.lookups.length, 0);
  assert.deepEqual(existing.actions, []);
});

test('disabling the custom preference restores original relaunch behavior', () => {
  const existing = browserWindow();
  const { calls } = run({ enabled: false, window: existing });
  assert.equal(calls.windows.length, 1);
  assert.equal(calls.lookups.length, 0);
  assert.deepEqual(existing.actions, []);
});

test('an explicit window action already handled upstream is not focused or duplicated', () => {
  const existing = browserWindow();
  const { calls } = run({ prevented: true, window: existing });
  assert.equal(calls.windows.length, 0);
  assert.equal(calls.lookups.length, 0);
  assert.deepEqual(existing.actions, []);
});

test('remaining command-line flags do not trigger argument-free reuse', () => {
  const existing = browserWindow();
  const { calls } = run({ args: ['--unknown-switch'], window: existing });
  assert.equal(calls.windows.length, 1);
  assert.equal(calls.lookups.length, 0);
  assert.deepEqual(existing.actions, []);
});

test('a remote URL retains existing external-URL routing', () => {
  const { calls, principal } = run({ args: ['https://example.com/'] });
  assert.equal(calls.routed.length, 1);
  assert.equal(calls.routed[0][0].spec, 'https://example.com/');
  assert.equal(calls.routed[0][1], 0);
  assert.equal(calls.routed[0][4], principal);
  assert.equal(calls.windows.length, 0);
  assert.equal(calls.lookups.length, 0);
});

test('Windows --osint --url dispatch still routes the external URL', () => {
  const { calls } = run({ args: ['--osint', '--url', 'https://example.com/'] });
  assert.equal(calls.routed.length, 1);
  assert.equal(calls.routed[0][0].spec, 'https://example.com/');
  assert.equal(calls.windows.length, 0);
  assert.equal(calls.lookups.length, 0);
});

test('a cold-start URL preserves opening the initial window with that URL', () => {
  const { calls } = run({ initial: true, args: ['https://example.com/'] });
  assert.equal(calls.routed.length, 0);
  assert.equal(calls.windows.length, 1);
  assert.deepEqual(Array.from(calls.windows[0][2]), ['https://example.com/']);
});

test('multiple URLs retain the original batch-window behavior', () => {
  const { calls } = run({ args: ['https://example.com/', 'https://example.org/'] });
  assert.equal(calls.routed.length, 0);
  assert.equal(calls.windows.length, 1);
  assert.deepEqual(Array.from(calls.windows[0][2]), ['https://example.com/', 'https://example.org/']);
});
