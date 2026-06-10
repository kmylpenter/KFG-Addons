#!/usr/bin/env node
// HARNESS_VERSION 1.0 — petla-noc characterization-test runner for Google Apps Script
//
// Usage: node harness.js <projectDir> [--json] [--filter <substr>] [--tests <dir>]
// Exit:  0 = all green | 1 = >=1 test failed (or source load error) | 2 = setup error
//
// Model: each TEST runs in a FRESH vm context (full isolation). All project *.gs
// sources are loaded into the context (top-level code runs, like GAS global scope),
// with GAS services mocked (see mocks.js). Test files: .petla-noc/tests/*.test.js
//   module.exports = { file: "Kod.gs", tests: [{ name, fixtures, run(g, state, assert) }] }
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const util = require("util");
const { buildMocks } = require(path.join(__dirname, "mocks.js"));

// ── args ─────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
const VALUE_FLAGS = new Set(["--filter", "--tests"]);
let projectDir = null, asJson = false, filter = null, testsDirArg = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--json") { asJson = true; continue; }
  if (VALUE_FLAGS.has(a)) {
    const v = argv[++i];
    if (a === "--filter") filter = v; else testsDirArg = v;
    continue;
  }
  if (!a.startsWith("--") && projectDir === null) projectDir = a;
}

function die(msg) {
  if (asJson) console.log(JSON.stringify({ setup_error: msg }));
  else console.error("SETUP ERROR: " + msg);
  process.exit(2);
}
if (!projectDir || !fs.existsSync(projectDir)) die(`project dir not found: ${projectDir}`);

const testsDir = testsDirArg || path.join(projectDir, ".petla-noc", "tests");
if (!fs.existsSync(testsDir)) die(`tests dir not found: ${testsDir} (modul B jeszcze nie utworzyl testow)`);

// ── collect sources (*.gs incl. _deprecated.gs; skip .petla-noc, node_modules) ──
// clasp projects keep sources as .js — accept .js too when appsscript.json exists.
const hasManifest = fs.existsSync(path.join(projectDir, "appsscript.json"));
function collectSources(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name.startsWith(".") || e.name === "node_modules") continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(...collectSources(p));
    else if (e.name.endsWith(".gs") || (hasManifest && e.name.endsWith(".js"))) out.push(p);
  }
  return out.sort(); // deterministic order (GAS uses manifest order; alpha is our convention)
}
const sources = collectSources(projectDir);
if (sources.length === 0) die(`no *.gs sources under ${projectDir}`);

const testFiles = fs.readdirSync(testsDir).filter((f) => f.endsWith(".test.js")).sort();
if (testFiles.length === 0) die(`no *.test.js in ${testsDir}`);

// ── tiny assert ──────────────────────────────────────────────────────────────
function makeAssert() {
  const fail = (msg) => { const e = new Error(msg); e._assert = true; throw e; };
  return {
    ok: (v, msg) => { if (!v) fail(msg || `expected truthy, got ${util.inspect(v)}`); },
    equal: (a, b, msg) => { if (a !== b) fail(msg || `expected ${util.inspect(b)}, got ${util.inspect(a)}`); },
    deepEqual: (a, b, msg) => {
      if (!util.isDeepStrictEqual(a, b)) fail(msg || `deepEqual failed:\n  got:      ${util.inspect(a)}\n  expected: ${util.inspect(b)}`);
    },
    throws: (fn, re, msg) => {
      try { fn(); } catch (e) {
        if (re && !String(e.message || e).match(re)) fail(msg || `threw, but message ${util.inspect(String(e.message))} !~ ${re}`);
        return;
      }
      fail(msg || "expected function to throw");
    },
  };
}

// ── run one test in a fresh context ──────────────────────────────────────────
function runTest(test) {
  const { globals, state } = buildMocks(test.fixtures || {});
  const sandbox = Object.assign({}, globals);
  const context = vm.createContext(sandbox);
  // preload: inject/override globals BEFORE sources run (top-level code may need them)
  if (typeof (test.fixtures || {}).preload === "function") test.fixtures.preload(context, state);
  const loadErrors = [];
  for (const src of sources) {
    const code = fs.readFileSync(src, "utf8");
    try {
      vm.runInContext(code, context, { filename: path.relative(projectDir, src), timeout: 10000 });
    } catch (e) {
      loadErrors.push(`${path.relative(projectDir, src)}: ${e.message}`);
    }
  }
  // top-level const/let are context-scoped, NOT context properties — expose an
  // escape hatch so tests can reach them: g.__eval('constFn(1,2)')
  context.__eval = (expr) => vm.runInContext(expr, context, { timeout: 10000 });
  if (typeof (test.fixtures || {}).extend === "function") test.fixtures.extend(context, state);
  if (loadErrors.length) return { status: "load_error", error: loadErrors.join(" | ") };
  try {
    test.run(context, state, makeAssert());
    return { status: "pass" };
  } catch (e) {
    return { status: e._assert ? "fail" : "error", error: String(e.message || e), stack: e._assert ? undefined : (e.stack || "").split("\n").slice(0, 4).join("\n") };
  }
}

// ── main ─────────────────────────────────────────────────────────────────────
const results = { project: path.basename(path.resolve(projectDir)), sources: sources.length, tests_total: 0, passed: 0, failed: 0, errors: 0, failures: [] };

for (const tf of testFiles) {
  let mod;
  try { mod = require(path.resolve(testsDir, tf)); }
  catch (e) { results.errors++; results.failures.push({ file: tf, test: "(load)", status: "error", error: String(e.message) }); continue; }
  const tests = (mod && mod.tests) || [];
  for (const t of tests) {
    if (filter && !t.name.includes(filter)) continue;
    results.tests_total++;
    const r = runTest(t);
    if (r.status === "pass") { results.passed++; continue; }
    if (r.status === "fail") results.failed++;
    else results.errors++;
    results.failures.push({ file: tf, source_file: mod.file || null, test: t.name, status: r.status, error: r.error, stack: r.stack });
  }
}

const green = results.failed === 0 && results.errors === 0 && results.tests_total > 0;
if (asJson) {
  console.log(JSON.stringify(Object.assign({ green }, results), null, 1));
} else {
  console.log(`harness: ${results.project} — ${results.passed}/${results.tests_total} passed` +
    (results.failed ? `, ${results.failed} FAILED` : "") + (results.errors ? `, ${results.errors} ERRORED` : ""));
  for (const f of results.failures) console.log(`  ✗ [${f.status}] ${f.file} :: ${f.test}\n    ${f.error}`);
}
process.exit(green ? 0 : 1);
