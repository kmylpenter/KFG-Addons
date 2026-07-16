#!/usr/bin/env node
// KFG Statusline v9.0 - ctx% │ model/ctx │ EFFORT │ project + linia limitow
// Effort detection: transcript JSONL > settings.json (same approach as ccstatusline)
// v9.0 (2026-07-16): lista zmienionych plikow USUNIETA (nieuzywana), w jej
//   miejsce kubelki 7d per-model z cache (serwer raportuje dzis jeden: "Fable"
//   = wspolny cap premium Opus+Fable). Linia limitow rozbita na dwa wiersze.

import { readFileSync, existsSync, writeFileSync, renameSync } from 'fs';
import { basename, join } from 'path';
import { homedir } from 'os';
import { spawn } from 'child_process';

const ESC = '\x1b';
const reset = `${ESC}[0m`;
const c_blue = `${ESC}[38;5;39m`;
const c_red = `${ESC}[38;5;196m`;
const c_cyan = `${ESC}[38;5;44m`;
const c_dim = `${ESC}[38;5;240m`;
const c_yellow = `${ESC}[38;5;220m`;
const c_violet = `${ESC}[38;5;135m`;
const c_pink = `${ESC}[38;5;205m`;   // project (tozsamosc, nie alarm)
const c_slate = `${ESC}[38;5;109m`;  // reset (czas do resetu)
const c_amber = `${ESC}[38;5;214m`;  // E: extra usage
const c_gold2 = `${ESC}[38;5;178m`;  // etykieta 7d (wartosc zostaje c_yellow 220)
// Kubelki 7d per-model. Kolor dobrany tak, by nie kolidowac z zadnym uzytym
// wyzej (39 model, 135 effort, 205 projekt, 44/51 5h, 178/220 7d, 109 reset,
// 214 extra) ani z gradientem ctx (46/154/226/208/202/196).
const c_orchid = `${ESC}[38;5;170m`; // cap per-model (dzis: wspolny premium Opus+Fable)

const SEP = `${c_dim} │ ${reset}`;

function getCtxColor(pct) {
  if (pct >= 85) return `${ESC}[38;5;196m`;
  if (pct >= 75) return `${ESC}[38;5;202m`;
  if (pct >= 65) return `${ESC}[38;5;208m`;
  if (pct >= 55) return `${ESC}[38;5;226m`;
  if (pct >= 40) return `${ESC}[38;5;154m`;
  return `${ESC}[38;5;46m`;
}

function getEffortColor(level) {
  // jeden kolor tozsamosci (fiolet) — poziom widac w napisie MAX/HIGH/MEDIUM/LOW;
  // nieznany/pending = dim. (Wczesniej high=blue kolidowal z modelem, medium=yellow z 7d.)
  return ['max', 'high', 'medium', 'low'].includes(level) ? c_violet : c_dim;
}

function shortModel(model, ctxWindowSize) {
  const id = model?.id || '';
  const name = model?.display_name || '';
  let ver = '';
  let m;
  if ((m = name.match(/(\d+\.\d+)/))) ver = m[1];
  else if ((m = id.match(/(\d+)-(\d+)-\d{8}/))) ver = `${m[1]}.${m[2]}`;
  else if ((m = id.match(/(\d+)-\d{8}/))) ver = m[1];
  else if ((m = id.match(/(\d+)-(\d+)/))) ver = `${m[1]}.${m[2]}`;

  const raw = id || name;
  let prefix = 'C';
  if (/opus/i.test(raw)) prefix = 'O';
  else if (/sonnet/i.test(raw)) prefix = 'S';
  else if (/haiku/i.test(raw)) prefix = 'H';

  let ctxSize = '';
  if (ctxWindowSize >= 1000000) ctxSize = `/${Math.round(ctxWindowSize / 1000000)}M`;
  else if (ctxWindowSize >= 1000) ctxSize = `/${Math.round(ctxWindowSize / 1000)}k`;

  return `${prefix}${ver}${ctxSize}`;
}

// Strip ANSI escape codes from text
function stripAnsi(str) {
  return str.replace(/\x1b\[[0-9;]*m/g, '');
}

// Read effort from transcript JSONL (per-session, based on ccstatusline approach)
// Scans from end for last /model or /effort command output
// Two formats:
//   /model: "<local-command-stdout>Set model to X with Y effort</local-command-stdout>"
//   /effort: "<local-command-stdout>Set effort level to Y ...</local-command-stdout>"
const MODEL_EFFORT_REGEX = /with\s+(low|medium|high|max)\s+effort/i;
const DIRECT_EFFORT_REGEX = /Set effort level to\s+(low|medium|high|max)/i;
// /effort command entry: <command-name>/effort</command-name>...<command-args>max</command-args>
const EFFORT_CMD_REGEX = /<command-name>\/effort<\/command-name>[\s\S]*<command-args>(low|medium|high|max)<\/command-args>/i;

function readEffortFromTranscript(transcriptPath) {
  if (!transcriptPath || !existsSync(transcriptPath)) return null;
  try {
    let content = readFileSync(transcriptPath, 'utf8');
    if (content.charCodeAt(0) === 0xFEFF) content = content.substring(1);
    const lines = content.split('\n');
    // Scan from end (most recent first)
    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i].trim();
      if (!line) continue;
      if (!line.includes('effort') && !line.includes('Set model to')) continue;
      try {
        const entry = JSON.parse(line);
        const text = entry?.message?.content;
        if (typeof text !== 'string') continue;
        const clean = stripAnsi(text);
        // /effort command entry (most reliable — parses user's actual command args)
        const cmdMatch = EFFORT_CMD_REGEX.exec(clean);
        if (cmdMatch) return cmdMatch[1].toLowerCase();
        // /effort stdout: "Set effort level to X ..."
        const directMatch = DIRECT_EFFORT_REGEX.exec(clean);
        if (directMatch) return directMatch[1].toLowerCase();
        // /model command: "Set model to X with Y effort"
        if (clean.includes('Set model to')) {
          const modelMatch = MODEL_EFFORT_REGEX.exec(clean);
          if (modelMatch) return modelMatch[1].toLowerCase();
          // /model without effort = effort was reset
          if (clean.includes('<local-command-stdout>Set model to')) return null;
        }
      } catch {}
    }
  } catch {}
  return null;
}

function resolveEffort(transcriptPath) {
  return readEffortFromTranscript(transcriptPath)
    || process.env.CLAUDE_CODE_EFFORT_LEVEL?.toLowerCase()
    || 'high';
}

try {
  let input = readFileSync(0, 'utf8');
  if (input.charCodeAt(0) === 0xFEFF) input = input.substring(1);
  if (!input.trim()) process.exit(0);

  const data = JSON.parse(input);

  // ===== usage-pace: segment tempa zuzycia limitow (DODATEK, nigdy nie psuje paska) =====
  // Czyta TYLKO stdin + cache (zero sieci). Odswieza wspolny cache max raz na 300 s
  // i wtedy odpala pace.sh w tle (odczepiony proces; logika progow = pace.sh, SSOT).
  let usageSegment = null;
  let spilloverAlert = null;
  try {
    const cachePath = process.env.CLAUDE_USAGE_CACHE_FILE || join(homedir(), '.claude', 'usage-cache.json');
    let cache = null;
    try { cache = JSON.parse(readFileSync(cachePath, 'utf8')); } catch {}
    const rl = data.rate_limits;
    const nowS = Date.now() / 1000;

    if (rl && (rl.seven_day || rl.five_hour)) {
      const age = nowS - ((cache && cache.fetched_at_epoch) || 0);
      if (age >= 300) {
        const upd = (cache && typeof cache === 'object') ? { ...cache } : {};
        const nb = (b) => (b && b.used_percentage != null)
          ? { used_pct: b.used_percentage, resets_at_epoch: b.resets_at } : undefined;
        const fh5 = nb(rl.five_hour), sd7 = nb(rl.seven_day);
        if (fh5) upd.five_hour = fh5;
        if (sd7) upd.seven_day = sd7;
        // extra usage ze stdin (jesli CC je przysyla) -> swiezsza kwota kredytow
        // niz 6h fetch z pace.sh; brak w stdin => nie ruszamy cache.
        if (rl.extra_usage && rl.extra_usage.used_credits != null) {
          upd.extra_usage = {
            is_enabled: !!rl.extra_usage.is_enabled,
            used_credits: rl.extra_usage.used_credits,
            currency: rl.extra_usage.currency,
            monthly_limit: rl.extra_usage.monthly_limit,
          };
        }
        upd.fetched_at_epoch = nowS;
        upd.source = 'statusline';
        if (data.version) upd.cc_version = data.version;
        const tmpPath = cachePath + '.tmp' + process.pid;
        writeFileSync(tmpPath, JSON.stringify(upd, null, 1));
        renameSync(tmpPath, cachePath);
        cache = upd;
        const paceSh = join(homedir(), '.claude', 'usage', 'pace.sh');
        if (existsSync(paceSh)) {
          // --refresh (nie --compute-only): pace.sh sam decyduje o ruchu do sieci
          // wg API_TTL_S i NIE wysyla powiadomien (te zostaja przy --scheduled).
          // Proces odczepiony — pasek nigdy na niego nie czeka.
          spawn('bash', [paceSh, '--refresh'], { detached: true, stdio: 'ignore' }).unref();
        }
      }
    }

    // dane do pokazania: stdin (zywe) > cache (jesli swiezszy niz 2 h)
    let fh = rl?.five_hour?.used_percentage;
    let sd = rl?.seven_day?.used_percentage;
    let fromCache = false;
    if (sd == null && cache?.seven_day?.used_pct != null
        && (nowS - (cache.fetched_at_epoch || 0)) < 7200) {
      fh = cache.five_hour?.used_pct;
      sd = cache.seven_day.used_pct;
      fromCache = true;
    }
    if (sd != null) {
      const pace = (cache && cache.pace) || {};
      const proj = pace.projection_pct;
      const proj5 = pace.projection_pct_5h;
      const st = pace.status;
      const c_green = `${ESC}[38;5;46m`;
      const c_cyanBri = `${ESC}[38;5;51m`;
      const bold = `${ESC}[1m`;

      // spill-over: PONAD 100% limitu. Czy REALNIE leca kredyty zalezy od
      // extra_usage.is_enabled: false = miesieczny limit (np. user €50) osiagniety
      // lub wylaczone -> twardy STOP, ZERO wydatkow. Wykrycie ponad-limitu z zywego
      // stdin (fh/sd); stan/kwota z cache.extra_usage.
      const overLimit = (fh != null && fh >= 100) || (sd != null && sd >= 100);
      const eu = (cache && cache.extra_usage) || null;
      const euKnown = !!eu;
      const euEnabled = !!(eu && eu.is_enabled);
      const c_orange = `${ESC}[38;5;208m`;
      let creditStr = '';
      if (eu && eu.used_credits != null && eu.used_credits > 0) {
        const sym = eu.currency === 'EUR' ? '€' : eu.currency === 'USD' ? '$' : (eu.currency ? eu.currency + ' ' : '');
        creditStr = `${sym}${(eu.used_credits / 100).toFixed(2)}`;
      }
      // znacznik segmentu 7d gdy ponad limit: ⚡ realnie wydaje | ⛔ zatkane | (brak) nieznane
      const overMark = overLimit ? (euEnabled ? '⚡' : euKnown ? '⛔' : '') : '';
      const overCol = (euEnabled || !euKnown) ? c_red : c_orange;
      // Ponad limit -> szczegoly TYLKO na osobnej linii (usage line zostaje waska).
      // Pod limitem -> dyskretne, KROTKIE "E: €X" (waski ekran telefonu).
      let extraInfo = '';
      if (overLimit && euEnabled) {
        spilloverAlert = creditStr
          ? `${bold}${c_red}⚡ EXTRA USAGE${reset}${c_dim} — ponad limit, leca kredyty: ${reset}${c_red}${creditStr}${reset}`
          : `${bold}${c_red}⚡ EXTRA USAGE${reset}${c_dim} — ponad limit, leca kredyty${reset}`;
      } else if (overLimit && euKnown) {
        spilloverAlert = `${bold}${c_orange}⛔ LIMIT PLANU${reset}${c_dim} — extra usage wył. (cap), bez wydatków${reset}`;
      } else if (creditStr) {
        extraInfo = `${c_amber}E: ${creditStr}${reset}`;
      }

      // czas do resetu okna -> zwięźle: "45m" / "2h10m" / "1d4h"
      const fmtDur = (epoch) => {
        if (epoch == null) return null;
        const s = Math.max(0, epoch - nowS);
        const d = Math.floor(s / 86400);
        const h = Math.floor((s % 86400) / 3600);
        const m = Math.floor((s % 3600) / 60);
        if (d >= 1) return `${d}d${h}h`;
        if (h >= 1) return `${h}h${m}m`;
        return `${m}m`;
      };

      // 5h: wartość jasny-cyjan, projekcja cyjan (informacyjna, bez alarmu)
      let s5 = '';
      if (fh != null) {
        const v = Math.round(fh);
        s5 = (proj5 != null)
          ? `${c_cyan}5h ${c_cyanBri}${v}${c_cyan}→${Math.min(999, Math.round(proj5))}%${reset}`
          : `${c_cyan}5h ${c_cyanBri}${v}%${reset}`;
      }

      // 7d: wartość żółta, projekcja pogrubiona w kolorze statusu (+⚠ przy LOW)
      const v7 = Math.round((pace.used_hwm != null) ? pace.used_hwm : sd);  // HWM = wartosc chroniona, spojna z projekcja (surowe sd bywa zglitchowane w dol)
      let s7;
      if (overLimit) s7 = `${c_gold2}7d ${bold}${overCol}${v7}%${overMark}${reset}`;  // ponad limit (⚡wydaje/⛔zatkane)
      else if (st === 'LOW' && proj != null) s7 = `${c_gold2}7d ${c_yellow}${v7}${bold}${c_red}→${Math.round(proj)}%⚠${reset}`;
      else if (st === 'OK' && proj != null) s7 = `${c_gold2}7d ${c_yellow}${v7}${bold}${c_green}→${Math.round(proj)}%${reset}`;
      else if (st === 'GRACE') s7 = `${c_gold2}7d ${c_yellow}${v7}${ESC}[38;5;250m→…${reset}`;  // swieze okno: projekcja niemiarodajna (liczy sie); jasny szary 250, bo dim 240 ginie na czarnym tle
      else if (proj != null && (st === 'STALE' || fromCache)) s7 = `${c_gold2}7d ${c_yellow}${v7}${c_dim}→?%${reset}`;
      else s7 = `${c_gold2}7d ${c_yellow}${v7}%${reset}`;

      // Kubelki 7d per-model — WYLACZNIE z cache (pasek nie chodzi do sieci;
      // odswieza je pace.sh --refresh spawnowany nizej).
      // Renderujemy KAZDY kubelek przyslany przez serwer, etykieta z jego
      // display_name — zamiast listy zaszytej w kodzie. Dzis przychodzi jeden:
      // "Fable" = wspolny cap premium (rosnie tez przy pracy na Opusie —
      // potwierdzone empirycznie 2026-07-16). Sonnet NIE jest raportowany
      // (serwer zwraca null nawet po realnym zuzyciu; potwierdzone w /usage),
      // dlatego nie ma dla niego wskaznika. Gdy Anthropic go kiedys wystawi,
      // pojawi sie tu sam — bez zmiany kodu.
      const scoped = (cache && Array.isArray(cache.model_scoped)) ? cache.model_scoped : [];
      const scopedSegs = scoped
        .filter(x => x && x.used_pct != null && x.display_name)
        .map(x => `${c_orchid}${x.display_name} ${Math.round(x.used_pct)}%${reset}`);

      // resety zgrupowane na końcu: "↺ 2h10m / 1d4h"
      const r5 = (rl && rl.five_hour && rl.five_hour.resets_at) || (cache && cache.five_hour && cache.five_hour.resets_at_epoch);
      const r7 = (rl && rl.seven_day && rl.seven_day.resets_at) || (cache && cache.seven_day && cache.seven_day.resets_at_epoch);
      const d5 = fmtDur(r5), d7 = fmtDur(r7);
      const resetSeg = (d5 || d7) ? `${c_slate}↺ ${d5 || '?'} / ${d7 || '?'}${reset}` : '';

      // separatory jak w linii 1 (SEP = " │ ") zamiast potrojnych spacji
      // Dwie linie zamiast jednej — na waskim ekranie (telefon/tablet w tmux)
      // wszystko w jednym wierszu sie nie miescilo i zawijalo sie brzydko.
      // Podzial wg sensu: ile zuzyto (okna + kubelki) | kiedy reset + kredyty.
      const usageRow1 = [s5, s7, ...scopedSegs].filter(Boolean).join(SEP);
      const usageRow2 = [resetSeg, extraInfo].filter(Boolean).join(SEP);
      usageSegment = [usageRow1, usageRow2].filter(Boolean).join('\n');
    }
  } catch {}
  // ===== koniec usage-pace =====

  // Context %
  let ctxPct = 0;
  let ctxWindowSize = 0;
  if (data.context_window) {
    ctxWindowSize = data.context_window.context_window_size || 0;
    if (data.context_window.used_percentage != null) {
      ctxPct = data.context_window.used_percentage;
    } else if (ctxWindowSize > 0 && data.context_window.current_usage) {
      const u = data.context_window.current_usage;
      const used = (u.input_tokens || 0) + (u.cache_creation_input_tokens || 0) + (u.cache_read_input_tokens || 0);
      ctxPct = Math.round((used / ctxWindowSize) * 100);
    }
  }

  const ctxColor = getCtxColor(ctxPct);
  const ctxStr = ctxPct > 100 ? '100%+' : `${ctxPct}%`;
  const modelName = shortModel(data.model, ctxWindowSize);
  const projectName = basename(data.cwd || data.workspace?.project_dir || '');

  // Effort level: transcript (per-session) > settings.json (global)
  const effort = resolveEffort(data.transcript_path);
  const effortColor = getEffortColor(effort);
  const effortIcon = `\x1b[1m${effort.toUpperCase()}\x1b[22m`;

  // Line 1: ctx% │ model │ EFFORT │ project
  const parts = [
    `${ctxColor}${ctxStr}${reset}`,
    `${c_blue}${modelName}${reset}`,
    `${effortColor}${effortIcon}${reset}`,
    `${c_pink}${projectName}${reset}`,
  ];
  let output = parts.join(SEP);

  // usage-pace: osobna linijka (pod glowna, nad lista plikow) — waski ekran
  if (usageSegment) output += `\n${usageSegment}`;
  if (spilloverAlert) output += `\n${spilloverAlert}`;

  process.stdout.write(output + '\n');
} catch {
  process.exit(0);
}
