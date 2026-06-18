#!/usr/bin/env node
// MUTATE_VERSION 1.1 — mutation tester for petla-noc characterization nets.
// 1.1: gate each source with EVERY *.test.js whose `file:` matches it (was: last-wins,
//      one test file per source — which undercounted kills massively for multi-test
//      sources like WorkTime.js[23 files]/TelegramBot.js[9], reporting false ~0% scores).
//
// Measures whether a test net DISCRIMINATES (would go RED if the code broke), not just
// whether it is green. A characterization test is green BY CONSTRUCTION; a test that
// SURVIVES a mutation is tautological coverage — it proves nothing. This is the machine
// form of the verify-before-done counterfactual ("a test must FAIL without the fix").
//
// Usage: node mutate.js <projectDir> [--source <file.gs>] [--max N] [--json] [--tests <dir>]
//   --source <f>  limit to one source file (default: every source that has a *.test.js gating it)
//   --max N       cap mutants per source file (default 40) — time-box; even-stride sampling
//   --tests <dir> tests dir (default <projectDir>/.petla-noc/tests)
//   --json        machine output (per-source scores + survivor sites)
//
// Reuses harness.js as SSOT via the PETLA_MUTATE override env — real source files are
// NEVER modified. Each mutant runs in a fresh harness process (full isolation).
//
// Classification per mutant:
//   KILLED   = a gating test asserted-fail or threw (the net caught the break) — GOOD
//   SURVIVED = all gating tests stayed green despite the break — a discrimination GAP
//   INVALID  = the mutant did not load (syntax broke) — excluded from the denominator
// mutation_score = killed / (killed + survived).
//
// Exit: 0 = ran (measurement, not a gate) | 2 = setup error.
"use strict";

const fs = require("fs");
const os = require("os");
const path = require("path");
const { spawnSync } = require("child_process");

const HARNESS = path.join(__dirname, "harness.js");

// ── args ─────────────────────────────────────────────────────────────────────
const argv = process.argv.slice(2);
let projectDir = null, sourceFilter = null, MAX = 40, asJson = false, testsDirArg = null;
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a === "--json") { asJson = true; continue; }
  if (a === "--source") { sourceFilter = argv[++i]; continue; }
  if (a === "--max") { MAX = parseInt(argv[++i], 10) || 40; continue; }
  if (a === "--tests") { testsDirArg = argv[++i]; continue; }
  if (!a.startsWith("--") && projectDir === null) projectDir = a;
}
function die(msg) {
  if (asJson) console.log(JSON.stringify({ setup_error: msg }));
  else console.error("SETUP ERROR: " + msg);
  process.exit(2);
}
if (!projectDir || !fs.existsSync(projectDir)) die(`project dir not found: ${projectDir}`);
const projAbs = path.resolve(projectDir);
const testsDir = testsDirArg ? path.resolve(testsDirArg) : path.join(projAbs, ".petla-noc", "tests");
if (!fs.existsSync(testsDir)) die(`tests dir not found: ${testsDir}`);

// capability guard: a pre-1.1 harness IGNORES PETLA_MUTATE and would report every mutant
// as SURVIVED (score 0) — a silent wrong result. Refuse rather than mislead.
try {
  if (!fs.readFileSync(HARNESS, "utf8").includes("PETLA_MUTATE"))
    die(`harness.js lacks PETLA_MUTATE support (HARNESS_VERSION < 1.1) — upgrade harness from templates (SKILL.md „Upgrade harnessu")`);
} catch (e) { die(`cannot read harness.js at ${HARNESS}: ${e.message}`); }

// ── map source file -> gating test file (via the test module's `file:` field) ──
const testFiles = fs.readdirSync(testsDir).filter((f) => f.endsWith(".test.js"));
const sourceToTest = {}; // absSourcePath -> [absTestPath, ...]  (ALL tests gating a source, not last-wins)
for (const tf of testFiles) {
  const abs = path.join(testsDir, tf);
  let mod;
  try { mod = require(abs); } catch { continue; } // unloadable test file — skip (canary's job)
  if (!mod || !mod.file) continue;
  const src = path.join(projAbs, mod.file);
  if (fs.existsSync(src)) {
    const key = path.resolve(src);
    (sourceToTest[key] || (sourceToTest[key] = [])).push(abs); // MUTATE 1.1: gate with EVERY test file, not just the last
  }
}
let targets = Object.keys(sourceToTest);
if (sourceFilter) {
  const want = path.resolve(projAbs, sourceFilter);
  targets = targets.filter((s) => s === want || path.basename(s) === sourceFilter);
}
if (targets.length === 0) die(`no source files with a gating *.test.js (filter: ${sourceFilter || "none"})`);

// ── mask string/comment bodies so operator scans never hit literals ────────────
function maskStringsAndComments(code) {
  const out = code.split("");
  const N = code.length;
  let i = 0, st = 0; // 0 none, 1 //, 2 /*, 3 ', 4 ", 5 `
  while (i < N) {
    const c = code[i], c2 = code[i + 1];
    if (st === 0) {
      if (c === "/" && c2 === "/") { out[i] = out[i + 1] = " "; i += 2; st = 1; continue; }
      if (c === "/" && c2 === "*") { out[i] = out[i + 1] = " "; i += 2; st = 2; continue; }
      if (c === "'") { st = 3; i++; continue; }
      if (c === '"') { st = 4; i++; continue; }
      if (c === "`") { st = 5; i++; continue; }
      i++; continue;
    }
    if (st === 1) { if (c === "\n") st = 0; else out[i] = " "; i++; continue; }
    if (st === 2) { if (c === "*" && c2 === "/") { out[i] = out[i + 1] = " "; i += 2; st = 0; continue; } if (c !== "\n") out[i] = " "; i++; continue; }
    // string/template: honor escapes, keep newlines for line counting
    if (c === "\\") { out[i] = " "; if (i + 1 < N && code[i + 1] !== "\n") out[i + 1] = " "; i += 2; continue; }
    if ((st === 3 && c === "'") || (st === 4 && c === '"') || (st === 5 && c === "`")) { st = 0; i++; continue; }
    if (c !== "\n") out[i] = " ";
    i++;
  }
  return out.join("");
}

function lastNonSpace(s, idx) { for (let j = idx; j >= 0; j--) if (s[j] !== " " && s[j] !== "\t") return s[j]; return null; }
function lineOf(code, idx) { let n = 1; for (let j = 0; j < idx; j++) if (code[j] === "\n") n++; return n; }
function lineText(code, line) { return (code.split("\n")[line - 1] || "").trim().slice(0, 120); }

// ── generate single-site mutants over the masked code ──────────────────────────
function genMutants(code) {
  const mask = maskStringsAndComments(code);
  const mut = [];
  const OPS = [["===", "!=="], ["!==", "==="], ["==", "!="], ["!=", "=="],
               ["<=", ">"], [">=", "<"], ["&&", "||"], ["||", "&&"]];
  let i = 0;
  while (i < mask.length) {
    if (mask.startsWith("=>", i)) { i += 2; continue; }       // arrow — never mutate
    let hit = null;
    for (const [op, rep] of OPS) if (mask.startsWith(op, i)) { hit = [op, rep]; break; }
    if (hit) { mut.push({ start: i, end: i + hit[0].length, before: hit[0], after: hit[1], op: "rel" }); i += hit[0].length; continue; }
    const c = mask[i];
    if (c === "<") { mut.push({ start: i, end: i + 1, before: "<", after: ">=", op: "rel" }); i++; continue; }
    if (c === ">") { mut.push({ start: i, end: i + 1, before: ">", after: "<=", op: "rel" }); i++; continue; }
    if (c === "+" || c === "-") {
      const next = mask[i + 1], prev = lastNonSpace(mask, i - 1);
      const binary = prev && /[\w$)\]]/.test(prev);            // skip unary; require a value before
      if (next !== c && next !== "=" && binary) mut.push({ start: i, end: i + 1, before: c, after: c === "+" ? "-" : "+", op: "arith" });
      i++; continue;
    }
    i++;
  }
  const reAdd = (re, mk) => { let m; while ((m = re.exec(mask))) mut.push(mk(m)); };
  reAdd(/\btrue\b/g, (m) => ({ start: m.index, end: m.index + 4, before: "true", after: "false", op: "bool" }));
  reAdd(/\bfalse\b/g, (m) => ({ start: m.index, end: m.index + 5, before: "false", after: "true", op: "bool" }));
  reAdd(/\b\d+\b/g, (m) => ({ start: m.index, end: m.index + m[0].length, before: m[0], after: String(parseInt(m[0], 10) + 1), op: "num" }));
  mut.sort((a, b) => a.start - b.start);
  return mut.map((x) => ({ ...x, line: lineOf(code, x.start) }));
}

function sampleEven(arr, n) {
  if (arr.length <= n) return arr;
  const out = [], step = arr.length / n;
  for (let j = 0; j < n; j++) out.push(arr[Math.floor(j * step)]);
  return out;
}

// ── classify one harness run ───────────────────────────────────────────────────
function classify(r) {
  let j;
  try { j = JSON.parse(r.stdout); } catch { return "invalid"; }
  if (j.setup_error) return "invalid";
  if (j.green === true) return "survived";
  const f = j.failures || [];
  if (f.length && f.every((x) => x.status === "load_error")) return "invalid";
  if (f.some((x) => x.status === "fail" || x.status === "error")) return "killed";
  return "invalid";
}

// ── run ────────────────────────────────────────────────────────────────────────
const work = fs.mkdtempSync(path.join(os.tmpdir(), "petla-mut-"));
const ovFile = path.join(work, "ov.json");
const results = [];
let aggKilled = 0, aggSurvived = 0, aggInvalid = 0;

for (const source of targets.sort()) {
  const rel = path.relative(projAbs, source);
  const code = fs.readFileSync(source, "utf8");
  const all = genMutants(code);
  const mutants = sampleEven(all, MAX);
  // tmp tests dir holding ALL of this source's gating tests (MUTATE 1.1: mutant killed if ANY gating test catches it)
  const tdir = fs.mkdtempSync(path.join(work, "t-"));
  for (const tfAbs of sourceToTest[source]) fs.copyFileSync(tfAbs, path.join(tdir, path.basename(tfAbs)));
  let killed = 0, survived = 0, invalid = 0;
  const survivors = [];
  for (const mu of mutants) {
    const mutated = code.slice(0, mu.start) + mu.after + code.slice(mu.end);
    fs.writeFileSync(ovFile, JSON.stringify({ [source]: mutated }));
    const r = spawnSync("node", [HARNESS, projAbs, "--tests", tdir, "--json"],
      { env: Object.assign({}, process.env, { PETLA_MUTATE: ovFile }), encoding: "utf8", timeout: 60000 });
    const cls = classify(r);
    if (cls === "killed") killed++;
    else if (cls === "survived") { survived++; survivors.push({ line: mu.line, op: mu.op, change: `${mu.before} -> ${mu.after}`, code: lineText(code, mu.line) }); }
    else invalid++;
  }
  fs.rmSync(tdir, { recursive: true, force: true });
  const denom = killed + survived;
  const score = denom ? +(killed / denom).toFixed(3) : null;
  aggKilled += killed; aggSurvived += survived; aggInvalid += invalid;
  results.push({ source: rel, test_files: sourceToTest[source].length, mutants_generated: all.length, mutants_run: mutants.length, killed, survived, invalid, score, survivors });
}
fs.rmSync(work, { recursive: true, force: true });

const aggDenom = aggKilled + aggSurvived;
const summary = {
  project: path.basename(projAbs),
  sources_tested: results.length,
  killed: aggKilled, survived: aggSurvived, invalid: aggInvalid,
  mutation_score: aggDenom ? +(aggKilled / aggDenom).toFixed(3) : null,
  results,
};

if (asJson) {
  console.log(JSON.stringify(summary, null, 1));
} else {
  console.log(`mutation: ${summary.project} — score ${summary.mutation_score} (${aggKilled} killed / ${aggSurvived} survived / ${aggInvalid} invalid) across ${results.length} files`);
  for (const r of results) {
    console.log(`  ${r.score === null ? "n/a " : (r.score * 100).toFixed(0).padStart(3) + "%"} ${r.source} (${r.killed}k/${r.survived}s/${r.invalid}i)`);
    for (const s of r.survivors) console.log(`      SURVIVED L${s.line} [${s.op}] ${s.change}  | ${s.code}`);
  }
}
process.exit(0);
