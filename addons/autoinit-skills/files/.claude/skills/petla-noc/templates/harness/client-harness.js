#!/usr/bin/env node
// CLIENT_HARNESS_VERSION 1.0 — petla-noc client characterization-test runner (.html logic).
//
// Each test runs in a FRESH vm context with the DOM + google.script.run shim (client-mocks.js).
// The gated .html file's INLINE <script> bodies are loaded into the context (external src=
// scripts are skipped). Covers client LOGIC; rendering/layout is the SMOKE layer's job.
// Test files: .petla-noc/tests-client/*.test.js
//   module.exports = { file: "index.html", tests: [{ name, fixtures, run(g, state, assert) }] }
//
// Usage: node client-harness.js <projectDir> [--json] [--filter <substr>] [--tests <dir>]
// Exit:  0 = all green | 1 = >=1 failed (or load error) | 2 = setup error. JSON shape == harness.js.
"use strict";

const fs = require("fs");
const path = require("path");
const vm = require("vm");
const util = require("util");
const { buildClientMocks } = require(path.join(__dirname, "client-mocks.js"));

const argv = process.argv.slice(2);
const VALUE_FLAGS = new Set(["--filter", "--tests"]);
let projectDir = null, asJson = false, filter = null, testsDirArg = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--json") { asJson = true; continue; }
  if (VALUE_FLAGS.has(a)) { const v = argv[++i]; if (a === "--filter") filter = v; else testsDirArg = v; continue; }
  if (!a.startsWith("--") && projectDir === null) projectDir = a;
}
function die(msg) { if (asJson) console.log(JSON.stringify({ setup_error: msg })); else console.error("SETUP ERROR: " + msg); process.exit(2); }
if (!projectDir || !fs.existsSync(projectDir)) die(`project dir not found: ${projectDir}`);
const testsDir = testsDirArg || path.join(projectDir, ".petla-noc", "tests-client");
if (!fs.existsSync(testsDir)) die(`client tests dir not found: ${testsDir} (FAZA POKRYCIA B-client jeszcze nie utworzyl testow)`);

const testFiles = fs.readdirSync(testsDir).filter((f) => f.endsWith(".test.js")).sort();
if (testFiles.length === 0) die(`no *.test.js in ${testsDir}`);

function extractScripts(html) {
  const out = [];
  const re = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html))) { if (/\bsrc\s*=/i.test(m[1])) continue; out.push(m[2]); } // skip external libs
  return out.join("\n;\n");
}

function makeAssert() {
  const fail = (msg) => { const e = new Error(msg); e._assert = true; throw e; };
  return {
    ok: (v, msg) => { if (!v) fail(msg || `expected truthy, got ${util.inspect(v)}`); },
    equal: (a, b, msg) => { if (a !== b) fail(msg || `expected ${util.inspect(b)}, got ${util.inspect(a)}`); },
    deepEqual: (a, b, msg) => { if (!util.isDeepStrictEqual(a, b)) fail(msg || `deepEqual failed:\n  got:      ${util.inspect(a)}\n  expected: ${util.inspect(b)}`); },
    throws: (fn, re, msg) => { try { fn(); } catch (e) { if (re && !String(e.message || e).match(re)) fail(msg || `threw, but ${util.inspect(String(e.message))} !~ ${re}`); return; } fail(msg || "expected throw"); },
  };
}

function runTest(test, scriptCode, fileLabel) {
  const { globals, state } = buildClientMocks(test.fixtures || {});
  const context = vm.createContext(Object.assign({}, globals));
  if (typeof (test.fixtures || {}).preload === "function") test.fixtures.preload(context, state);
  let loadError = null;
  try { vm.runInContext(scriptCode, context, { filename: fileLabel, timeout: 10000 }); }
  catch (e) { loadError = e.message; }
  context.__eval = (expr) => vm.runInContext(expr, context, { timeout: 10000 });
  if (typeof (test.fixtures || {}).extend === "function") test.fixtures.extend(context, state);
  if (loadError) return { status: "load_error", error: loadError };
  try { test.run(context, state, makeAssert()); return { status: "pass" }; }
  catch (e) { return { status: e._assert ? "fail" : "error", error: String(e.message || e), stack: e._assert ? undefined : (e.stack || "").split("\n").slice(0, 4).join("\n") }; }
}

const results = { project: path.basename(path.resolve(projectDir)), sources: 0, tests_total: 0, passed: 0, failed: 0, errors: 0, failures: [] };
const htmlCache = {};

for (const tf of testFiles) {
  let mod;
  try { mod = require(path.resolve(testsDir, tf)); }
  catch (e) { results.errors++; results.failures.push({ file: tf, test: "(load)", status: "error", error: String(e.message) }); continue; }
  const htmlRel = mod.file;
  let scriptCode = htmlCache[htmlRel];
  if (scriptCode === undefined) {
    const htmlPath = path.join(projectDir, htmlRel || "");
    if (!htmlRel || !fs.existsSync(htmlPath)) { scriptCode = null; }
    else { scriptCode = extractScripts(fs.readFileSync(htmlPath, "utf8")); results.sources++; }
    htmlCache[htmlRel] = scriptCode;
  }
  for (const t of (mod.tests || [])) {
    if (filter && !t.name.includes(filter)) continue;
    results.tests_total++;
    if (scriptCode === null) { results.errors++; results.failures.push({ file: tf, source_file: htmlRel, test: t.name, status: "load_error", error: `html not found: ${htmlRel}` }); continue; }
    const r = runTest(t, scriptCode, htmlRel);
    if (r.status === "pass") { results.passed++; continue; }
    if (r.status === "fail") results.failed++; else results.errors++;
    results.failures.push({ file: tf, source_file: htmlRel, test: t.name, status: r.status, error: r.error, stack: r.stack });
  }
}

const green = results.failed === 0 && results.errors === 0 && results.tests_total > 0;
if (asJson) console.log(JSON.stringify(Object.assign({ green }, results), null, 1));
else {
  console.log(`client-harness: ${results.project} — ${results.passed}/${results.tests_total} passed` + (results.failed ? `, ${results.failed} FAILED` : "") + (results.errors ? `, ${results.errors} ERRORED` : ""));
  for (const f of results.failures) console.log(`  ✗ [${f.status}] ${f.file} :: ${f.test}\n    ${f.error}`);
}
process.exit(green ? 0 : 1);
