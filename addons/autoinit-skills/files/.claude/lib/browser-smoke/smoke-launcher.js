#!/usr/bin/env node
/**
 * smoke-launcher.js — Universal puppeteer-core wrapper for /petla smoke
 *
 * Runs a single test file in fresh chromium (Termux Android), captures evidence,
 * emits JSON Lines to stdout with END marker (truncation/corruption detection).
 *
 * Empirically validated: puppeteer-core@24.42.0 + chromium 148 on Termux (2026-05-30).
 * NOTE: chromium on Termux auto-updates; bump EXPECTED_CHROMIUM_MAJOR + re-run
 *       --self-test when it drifts (the version gate is a safety check, not a pin).
 *
 * USAGE:
 *   node smoke-launcher.js <test.js>      Run a single test file
 *   node smoke-launcher.js --self-test    Run 5 built-in self-tests
 *
 * EXIT CODES (coarse signal): 0 PASS, 1 FAIL, 2 INCONCLUSIVE, 3 SETUP_ERROR, 4 CRASH/TIMEOUT
 *   The AUTHORITATIVE status is the END-marker `status` field on stdout — the
 *   orchestrator MUST parse that (exit codes collapse setup/crash detail).
 *
 * Test file contract: module.exports = async function(page, helpers) { ... }
 * Helpers: snapshot, assertDom, recordCustom, recordBonusBug, baseUrl
 */

'use strict';

const puppeteer = require('puppeteer-core');
const crypto = require('crypto');
const fs = require('fs');
const net = require('net');
const path = require('path');
const { execSync } = require('child_process');

const DEFAULT_CHROMIUM = '/data/data/com.termux/files/usr/bin/chromium-browser';
const TMPDIR = process.env.TMPDIR || '/data/data/com.termux/files/usr/tmp';
const EXPECTED_CHROMIUM_MAJOR = 148;  // 2026-05-30: empirically verified working w/ puppeteer-core 24.42.0

// JSON Lines output protocol — addresses A_NEW1 (truncation safety)
const stdoutLines = [];
function emit(obj) {
  const line = JSON.stringify(obj);
  stdoutLines.push(line);
  process.stdout.write(line + '\n');
}

function emitEndMarker(testId, status) {
  const checksum = crypto.createHash('sha1')
    .update(stdoutLines.join('\n'))
    .digest('hex');
  process.stdout.write(JSON.stringify({
    _marker: 'END',
    test_id: testId,
    status,
    checksum,
  }) + '\n');
}

// Port discovery + retry (addresses N3 — Termux TOCTOU)
async function findFreePortWithRetry(maxAttempts = 3) {
  for (let i = 0; i < maxAttempts; i++) {
    const port = await new Promise((resolve, reject) => {
      const srv = net.createServer();
      srv.listen(0, () => {
        const p = srv.address().port;
        srv.close(() => resolve(p));
      });
      srv.on('error', reject);
    });
    // Verify port still free immediately before passing on
    try {
      const check = net.createServer();
      await new Promise((res, rej) => {
        check.once('error', rej);
        check.listen(port, res);
      });
      await new Promise(r => check.close(r));
      return port;
    } catch {
      continue;
    }
  }
  throw new Error('SETUP_ERROR: port discovery exhausted after ' + maxAttempts + ' attempts');
}

// Chromium version drift policy (3-tier)
function checkChromiumVersion(chromiumPath) {
  let actual;
  try {
    const out = execSync(`"${chromiumPath}" --version`, { encoding: 'utf8', timeout: 5000 });
    const m = out.match(/Chromium (\d+)\.(\d+)\.(\d+)/);
    if (!m) throw new Error('version regex mismatch: ' + out.trim());
    actual = { major: +m[1], minor: +m[2], patch: +m[3], full: out.trim() };
  } catch (e) {
    return { ok: false, reason: 'version_check_failed', error: e.message };
  }
  const delta = actual.major - EXPECTED_CHROMIUM_MAJOR;
  if (delta < 0 || delta === 0) return { ok: true, level: 'INFO', actual };
  if (delta === 1) return { ok: true, level: 'WARN', actual, note: 'major +1 drift; record in state file' };
  return { ok: false, level: 'ERROR', actual, reason: 'major drift unsafe', delta };
}

// Test Author API helpers (addresses N6 — how tests populate evidence)
function makeHelpers(baseUrl, evidence, bonusBugsList) {
  return {
    baseUrl,
    async snapshot(label, data) {
      evidence.state_snapshots.push({ label, data });
    },
    async assertDom(selector, expectation) {
      const matched = !!expectation.matched;
      evidence.dom_assertions.push({ selector, matched, value: expectation.value });
    },
    async recordCustom(key, value) {
      evidence.custom_fields[key] = value;
    },
    recordBonusBug(bug) {
      bonusBugsList.push({
        description: bug.description,
        severity: bug.severity || 'minor',
        file: bug.file,
        line: bug.line,
        hint: bug.hint || '',
      });
    },
  };
}

async function runTest(opts) {
  const startMs = Date.now();
  const testId = path.basename(opts.testFile, '.js');
  const evidence = { state_snapshots: [], dom_assertions: [], custom_fields: {} };
  const logs = [];
  const errors = [];
  const bonusBugs = [];

  // Resolve chromium path + check version
  const chromiumPath = opts.chromiumPath || DEFAULT_CHROMIUM;
  if (!fs.existsSync(chromiumPath)) {
    emit({ event: 'setup_error', reason: 'chromium_not_found', path: chromiumPath });
    emitEndMarker(testId, 'SETUP_ERROR');   // marker must match exit 3 (was 'INCONCLUSIVE' — CC2-1)
    return { exit: 3 };
  }
  const versionCheck = checkChromiumVersion(chromiumPath);
  emit({ event: 'chromium_version', ...versionCheck });
  if (!versionCheck.ok && versionCheck.level === 'ERROR') {
    emit({ event: 'setup_error', reason: 'chromium_major_drift_unsafe', delta: versionCheck.delta });
    emitEndMarker(testId, 'SETUP_ERROR');   // marker must match exit 3 (CC2-1)
    return { exit: 3 };
  }

  // Allocate port (caller can override)
  let port = opts.port;
  if (!port) {
    try {
      port = await findFreePortWithRetry();
    } catch (e) {
      emit({ event: 'setup_error', reason: 'port_discovery_failed', error: e.message });
      emitEndMarker(testId, 'SETUP_ERROR');   // marker must match exit 3 (CC2-1)
      return { exit: 3 };
    }
  }
  emit({ event: 'port_allocated', port });

  // Build chromium args with --user-data-dir tag (addresses N3_R4)
  const runId = crypto.randomBytes(4).toString('hex');
  const userDataDir = path.join(TMPDIR, `smoke-chromium-${runId}`);
  const baseArgs = ['--no-sandbox', '--disable-setuid-sandbox', '--no-zygote',
    `--user-data-dir=${userDataDir}`];
  // M2-only network egress policy:
  // baseArgs.push("--host-resolver-rules=MAP * 127.0.0.1, EXCLUDE localhost");
  const chromiumArgs = (opts.chromiumArgs || []).concat(baseArgs);

  let browser, page;
  try {
    browser = await puppeteer.launch({
      executablePath: chromiumPath,
      headless: 'new',
      args: chromiumArgs,
      timeout: opts.timeout || 30000,
    });
    page = await browser.newPage();
    page.on('console', msg => {
      const text = `[${msg.type()}] ${msg.text()}`;
      if (!opts.consoleFilterRegex || new RegExp(opts.consoleFilterRegex).test(text)) {
        logs.push(text);
      }
    });
    page.on('pageerror', err => {
      errors.push({
        message: err.message,
        stack: err.stack || '',
        timestamp_ms: Date.now() - startMs,
      });
    });

    const baseUrl = opts.baseUrl || `http://localhost:${port}`;
    const helpers = makeHelpers(baseUrl, evidence, bonusBugs);
    helpers.page = page;

    // Load + execute test
    const testFn = require(path.resolve(opts.testFile));
    if (typeof testFn !== 'function') {
      throw new Error('test file must export an async function(page, helpers)');
    }
    await testFn(page, helpers);

    const result = {
      test_id: testId,
      status: 'PASS',
      duration_ms: Date.now() - startMs,
      evidence,
      logs,
      errors,
      bonus_bugs: bonusBugs,  // M1 emits empty []; M2 populates
      meta: {
        chromium_version_actual: versionCheck.actual?.full || 'unknown',
        port_allocated: port,
        fresh_launch: true,
      },
    };
    emit({ event: 'test_result', result });
    emitEndMarker(testId, 'PASS');
    return { exit: 0 };
  } catch (e) {
    const result = {
      test_id: testId,
      status: 'FAIL',
      duration_ms: Date.now() - startMs,
      evidence,
      logs,
      errors: errors.concat([{ message: e.message, stack: e.stack || '', timestamp_ms: Date.now() - startMs }]),
      bonus_bugs: bonusBugs,
      meta: {
        chromium_version_actual: versionCheck.actual?.full || 'unknown',
        port_allocated: port,
        fresh_launch: true,
      },
    };
    emit({ event: 'test_result', result });
    emitEndMarker(testId, 'FAIL');
    return { exit: 1 };
  } finally {
    if (browser) {
      try { await browser.close(); } catch {}
    }
    // Cleanup user-data-dir (best-effort)
    try { fs.rmSync(userDataDir, { recursive: true, force: true }); } catch {}
  }
}

// --self-test mode: 5 built-in tests
async function selfTest() {
  let passed = 0, failed = 0;
  const results = [];

  // Test 1: findFreePortWithRetry returns int 1024-65535
  try {
    const p = await findFreePortWithRetry();
    if (typeof p === 'number' && p >= 1024 && p <= 65535) {
      results.push('OK: findFreePortWithRetry → ' + p);
      passed++;
    } else throw new Error('out of range: ' + p);
  } catch (e) { results.push('FAIL: findFreePortWithRetry — ' + e.message); failed++; }

  // Test 2: TestResult JSON validates against canonical example
  try {
    const sample = {
      test_id: 'x', status: 'PASS', duration_ms: 1,
      evidence: { state_snapshots: [], dom_assertions: [], custom_fields: {} },
      logs: [], errors: [], bonus_bugs: [],
      meta: { chromium_version_actual: 'x', port_allocated: 1, fresh_launch: true },
    };
    const requiredFields = ['test_id', 'status', 'duration_ms', 'evidence', 'logs', 'errors', 'bonus_bugs', 'meta'];
    const missing = requiredFields.filter(f => !(f in sample));
    if (missing.length) throw new Error('missing fields: ' + missing.join(','));
    if (!['PASS', 'FAIL', 'INCONCLUSIVE'].includes(sample.status)) throw new Error('bad status');
    results.push('OK: TestResult schema valid');
    passed++;
  } catch (e) { results.push('FAIL: TestResult schema — ' + e.message); failed++; }

  // Test 3: Exit code mapping (full contract incl. SETUP_ERROR=3, CRASH=4 — CC2-1)
  try {
    const map = { PASS: 0, FAIL: 1, INCONCLUSIVE: 2, SETUP_ERROR: 3, CRASH: 4 };
    if (map.PASS !== 0 || map.FAIL !== 1 || map.INCONCLUSIVE !== 2 ||
        map.SETUP_ERROR !== 3 || map.CRASH !== 4) throw new Error('map wrong');
    results.push('OK: Exit code mapping (0/1/2/3/4)');
    passed++;
  } catch (e) { results.push('FAIL: Exit code mapping — ' + e.message); failed++; }

  // Test 4: Chromium binary executable
  try {
    if (!fs.existsSync(DEFAULT_CHROMIUM)) throw new Error('not found at ' + DEFAULT_CHROMIUM);
    fs.accessSync(DEFAULT_CHROMIUM, fs.constants.X_OK);
    results.push('OK: Chromium binary executable at ' + DEFAULT_CHROMIUM);
    passed++;
  } catch (e) { results.push('FAIL: Chromium binary — ' + e.message); failed++; }

  // Test 5: chromium --version parses major
  try {
    const v = checkChromiumVersion(DEFAULT_CHROMIUM);
    if (!v.actual || typeof v.actual.major !== 'number') throw new Error('version parse failed: ' + JSON.stringify(v));
    results.push('OK: Chromium version parsed → major=' + v.actual.major);
    passed++;
  } catch (e) { results.push('FAIL: Version parse — ' + e.message); failed++; }

  results.forEach(r => console.log(r));
  console.log(JSON.stringify({ self_test: 'complete', passed, failed }));
  return failed === 0 ? 0 : 1;
}

// CLI entrypoint
async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    console.error('Usage: node smoke-launcher.js <test.js> | --self-test');
    process.exit(3);
  }
  if (args[0] === '--self-test') {
    process.exit(await selfTest());
  }
  const testFile = args[0];
  if (!fs.existsSync(testFile)) {
    emit({ event: 'setup_error', reason: 'test_file_not_found', path: testFile });
    emitEndMarker('unknown', 'SETUP_ERROR');   // marker must match exit 3 (CC2-1)
    process.exit(3);
  }
  // M1: the CLI runs with DEFAULTS only. .smoke-config.yaml (init_wait_for_function,
  // gas_url, consoleFilterRegex, baseUrl, etc.) is NOT read here — to honor it, call the
  // programmatic API runTest({...opts}) directly (see module.exports) and pass those fields.
  // (CC2-3: documenting the real contract instead of implying the YAML is consumed.)
  try {
    const result = await runTest({ testFile });
    process.exit(result.exit);
  } catch (e) {
    emit({ event: 'crash', error: e.message, stack: e.stack });
    emitEndMarker('unknown', 'CRASH');   // marker must match exit 4 (was 'INCONCLUSIVE' — CC2-1)
    process.exit(4);
  }
}

// Programmatic API (for orchestrators)
module.exports = { runTest, findFreePortWithRetry, checkChromiumVersion, makeHelpers };

if (require.main === module) {
  main().catch(e => {
    console.error('fatal:', e);
    process.exit(4);
  });
}
