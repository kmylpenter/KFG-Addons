#!/usr/bin/env python3
"""
TOOLS_POTENTIAL analyzer — deterministyczna agregacja logów Claude Code (JSONL).

Cel: wskazać MECHANICZNE czynności (stabilne wejście->wyjście, zero osądu/NLU),
które Claude wykonuje wielokrotnie rozumowaniem LLM, a deterministyczny skrypt
zrobiłby za darmo. Liczy częstość + przypisane tokeny OUTPUT (redukowalny koszt
inferencji) per tura, rozdziela cap MAIN (opus/fable) od SONNET (osobny limit).

NIE używa LLM. Czyste parsowanie/zliczanie. Okno: ostatnie 7 dni (per-event ts).
"""
import os, re, json, sys
from datetime import datetime, timezone, timedelta
from collections import defaultdict

ROOT = os.path.expanduser('~/.claude/projects')
NOW = datetime.now(timezone.utc)
CUTOFF = NOW - timedelta(days=7)
FILE_MTIME_FLOOR = (NOW - timedelta(days=8)).timestamp()  # bufor na granicy

def model_family(m):
    if not m: return 'OTHER'
    m = m.lower()
    if 'synthetic' in m: return 'SYNTH'
    if 'opus' in m or 'fable' in m: return 'MAIN'
    if 'sonnet' in m: return 'SONNET'
    if 'haiku' in m: return 'HAIKU'
    return 'OTHER'

def shortproj(dirpath):
    b = os.path.basename(dirpath)
    tmx = b.startswith('-data-data-com-termux')
    m = re.search(r'projekty-(.+)$', b)
    if m: name = m.group(1)
    elif b.endswith('projekty'): name = '(projekty-root)'
    elif b.endswith('-home'): name = '(home)'
    else: name = b
    if tmx: name += ' [tmx]'
    return name

def parse_ts(ts):
    if not ts: return None
    try:
        return datetime.fromisoformat(ts.replace('Z', '+00:00'))
    except Exception:
        return None

# ---- bash command normalization ----
ENVASSIGN = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=')
WRAPPERS = {'sudo','time','nice','nohup','env','command','exec','xargs','timeout','stdbuf'}

def bash_program(cmd):
    """Pierwszy realny program komendy (po zdjęciu cd/env/wrapperów)."""
    c = cmd.strip()
    # zdejmij wiodące `cd X &&` / `cd X ;`
    c = re.sub(r'^\s*cd\s+[^\s;&]+\s*(&&|;)\s*', '', c)
    # weź pierwszy segment przed |, &&, ;, nowa linia
    seg = re.split(r'\n|\|\||&&|\||;', c, maxsplit=1)[0].strip()
    toks = seg.split()
    i = 0
    while i < len(toks) and (ENVASSIGN.match(toks[i]) or toks[i] in WRAPPERS):
        i += 1
    if i >= len(toks):
        return '(empty)', []
    prog = toks[i]
    prog = os.path.basename(prog)  # /usr/bin/python3 -> python3
    return prog, toks[i+1:]

SUBCMD_PROGS = {'git','npm','npx','clasp','uv','pip','pip3','docker','gh','cargo',
                'go','tldr','apt','apt-get','yarn','pnpm','systemctl','kubectl',
                'pm2','poetry','conda','brew','bun','deno'}

def bash_progsub(cmd):
    prog, rest = bash_program(cmd)
    if prog in SUBCMD_PROGS:
        for t in rest:
            if not t.startswith('-'):
                return f'{prog} {t}'
        return prog
    if prog in ('python3','python','py'):
        # python3 script.py  vs  python3 - <<HEREDOC  vs python3 -c
        for t in rest:
            if t == '-' or t == '-c':
                return f'{prog} -c/inline'
            if t.endswith('.py'):
                return f'{prog} {os.path.basename(t)}'
            if not t.startswith('-'):
                return f'{prog} {os.path.basename(t)}'
        return f'{prog} inline'
    if prog == 'bash' or prog == 'sh':
        for t in rest:
            if t.endswith('.sh'):
                return f'{prog} {os.path.basename(t)}'
            if not t.startswith('-'):
                return f'{prog} script'
        return f'{prog} -c'
    return prog

def bash_template(cmd):
    """Strukturalny szablon: ten sam kształt komendy z różnymi argumentami -> ten sam klucz."""
    t = cmd.strip()
    # collapse heredoc body
    t = re.sub(r"<<-?\s*'?\w+'?[\s\S]*", ' <<HEREDOC', t)
    # newlines -> spacje
    t = t.replace('\n', ' ')
    # quoted strings -> S
    t = re.sub(r'"[^"]*"', '"S"', t)
    t = re.sub(r"'[^']*'", "'S'", t)
    # absolutne/relatywne ścieżki -> PATH (po stringach)
    t = re.sub(r'(?<!\w)~?/[^\s"\'|;&>]*', 'PATH', t)
    t = re.sub(r'(?<![\w/])\./[^\s"\'|;&>]*', 'PATH', t)
    # hex/uuid -> HEX, liczby -> N
    t = re.sub(r'\b[0-9a-f]{7,}\b', 'HEX', t)
    t = re.sub(r'\b\d+\b', 'N', t)
    t = re.sub(r'\s+', ' ', t).strip()
    return t[:160]

def exact_norm(cmd):
    t = re.sub(r"<<-?\s*'?\w+'?[\s\S]*", ' <<HEREDOC', cmd.strip())
    t = re.sub(r'\s+', ' ', t.replace('\n', ' ')).strip()
    return t[:200]

# ---- akumulatory ----
glob_tok = defaultdict(lambda: dict(turns=0, out=0, inp=0, cc=0, cr=0))   # family -> tokens
proj_tok = defaultdict(lambda: dict(turns=0, out_main=0, out_son=0, out_oth=0, cr=0, cc=0))
tool_stats = defaultdict(lambda: dict(calls=0, out_main=0, out_son=0, calls_main=0, calls_son=0))
bash_prog = defaultdict(lambda: dict(n=0, out=0, projs=set(), main=0, son=0))
bash_ps   = defaultdict(lambda: dict(n=0, out=0, projs=set(), main=0, son=0))
bash_tmpl = defaultdict(lambda: dict(n=0, out=0, projs=set(), main=0, son=0, ex=''))
bash_exact= defaultdict(lambda: dict(n=0, out=0, projs=set()))
read_files = defaultdict(int)              # (proj, path) -> count
read_total = dict(n=0, out=0, main=0)
grep_stats = dict(n=0, out=0)
glob_stats = dict(n=0, out=0)
seq_bigram = defaultdict(int)              # (toolA, toolB) consecutive turns
bash_bigram = defaultdict(int)             # (progA, progB) consecutive bash turns
sidechain = dict(turns=0, out=0)
n_files = 0
n_turns_total = 0
n_turns_tool = 0
n_turns_text = 0

session_lastprimary = {}   # sessionId -> last primary tool
session_lastbashprog = {}  # sessionId -> last bash prog

def add_proj(proj, fam, u):
    p = proj_tok[proj]
    p['turns'] += 1
    p['cr'] += u.get('cache_read_input_tokens', 0) or 0
    p['cc'] += u.get('cache_creation_input_tokens', 0) or 0
    o = u.get('output_tokens', 0) or 0
    if fam == 'MAIN': p['out_main'] += o
    elif fam == 'SONNET': p['out_son'] += o
    else: p['out_oth'] += o

for dirpath, _, files in os.walk(ROOT):
    for fn in files:
        if not fn.endswith('.jsonl'):
            continue
        fp = os.path.join(dirpath, fn)
        try:
            if os.path.getmtime(fp) < FILE_MTIME_FLOOR:
                continue
        except OSError:
            continue
        proj = shortproj(dirpath)
        n_files += 1
        try:
            fh = open(fp, 'r', errors='replace')
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"assistant"' not in line:
                    continue
                try:
                    o = json.loads(line)
                except Exception:
                    continue
                if o.get('type') != 'assistant':
                    continue
                ts = parse_ts(o.get('timestamp'))
                if ts is not None and ts < CUTOFF:
                    continue
                msg = o.get('message') or {}
                fam = model_family(msg.get('model'))
                if fam == 'SYNTH':
                    continue
                u = msg.get('usage') or {}
                out = u.get('output_tokens', 0) or 0
                sid = o.get('sessionId') or fp
                # globalne
                g = glob_tok[fam]
                g['turns'] += 1
                g['out'] += out
                g['inp'] += u.get('input_tokens', 0) or 0
                g['cc'] += u.get('cache_creation_input_tokens', 0) or 0
                g['cr'] += u.get('cache_read_input_tokens', 0) or 0
                add_proj(proj, fam, u)
                n_turns_total += 1
                if o.get('isSidechain'):
                    sidechain['turns'] += 1
                    sidechain['out'] += out

                content = msg.get('content')
                tools = []
                if isinstance(content, list):
                    for b in content:
                        if isinstance(b, dict) and b.get('type') == 'tool_use':
                            tools.append((b.get('name'), b.get('input') or {}))
                if not tools:
                    n_turns_text += 1
                    primary = 'TEXT'
                else:
                    n_turns_tool += 1
                    primary = tools[0][0]
                    share = out / len(tools)
                    for name, inp in tools:
                        t = tool_stats[name]
                        t['calls'] += 1
                        if fam == 'MAIN':
                            t['out_main'] += share; t['calls_main'] += 1
                        elif fam == 'SONNET':
                            t['out_son'] += share; t['calls_son'] += 1
                        # --- per-tool deep dive ---
                        if name == 'Bash':
                            cmd = inp.get('command', '') or ''
                            if cmd.strip():
                                try:
                                    pr = bash_program(cmd)
                                    prog = pr[0] if isinstance(pr, tuple) else pr
                                except Exception:
                                    prog = '(parse-err)'
                                ps = bash_progsub(cmd)
                                tm = bash_template(cmd)
                                ex = exact_norm(cmd)
                                for d, key in ((bash_prog, prog), (bash_ps, ps), (bash_tmpl, tm)):
                                    e = d[key]
                                    e['n'] += 1; e['out'] += share; e['projs'].add(proj)
                                    if fam == 'MAIN': e['main'] += 1
                                    elif fam == 'SONNET': e['son'] += 1
                                bash_tmpl[tm]['ex'] = bash_tmpl[tm]['ex'] or ex
                                ee = bash_exact[ex]
                                ee['n'] += 1; ee['out'] += share; ee['projs'].add(proj)
                                # bash bigram per session
                                lp = session_lastbashprog.get(sid)
                                if lp is not None:
                                    bash_bigram[(lp, prog)] += 1
                                session_lastbashprog[sid] = prog
                        elif name == 'Read':
                            fpth = inp.get('file_path', '') or ''
                            read_total['n'] += 1; read_total['out'] += share
                            if fam == 'MAIN': read_total['main'] += share
                            if fpth:
                                read_files[(proj, fpth)] += 1
                        elif name == 'Grep':
                            grep_stats['n'] += 1; grep_stats['out'] += share
                        elif name == 'Glob':
                            glob_stats['n'] += 1; glob_stats['out'] += share
                # sekwencja tur (primary tool)
                lp = session_lastprimary.get(sid)
                if lp is not None:
                    seq_bigram[(lp, primary)] += 1
                session_lastprimary[sid] = primary

# ===================== RAPORT =====================
def f(n): return f'{int(round(n)):,}'.replace(',', ' ')

print('#'*70)
print('TOOLS_POTENTIAL — agregat logów Claude Code (ostatnie 7 dni)')
print(f'okno: {CUTOFF.isoformat()}  ..  {NOW.isoformat()}')
print(f'plików przetworzonych: {n_files}')
print('#'*70)

print('\n=== 1. GLOBAL TOKENS per model-family (tury = wywołania API) ===')
print(f'{"family":8} {"turns":>7} {"output":>12} {"input_new":>12} {"cache_creat":>12} {"cache_read":>13}')
tot_out_main = 0
for fam in ('MAIN','SONNET','HAIKU','OTHER'):
    g = glob_tok.get(fam)
    if not g: continue
    if fam == 'MAIN': tot_out_main = g['out']
    print(f'{fam:8} {g["turns"]:>7} {f(g["out"]):>12} {f(g["inp"]):>12} {f(g["cc"]):>12} {f(g["cr"]):>13}')
print(f'\ntury łącznie: {n_turns_total}  | z tool_use: {n_turns_tool}  | text-only: {n_turns_text}')
print(f'sidechain (subagent) tury: {sidechain["turns"]}  output: {f(sidechain["out"])}')
print(f'>>> OUTPUT MAIN (wspólny cap Opus/Fable) = {f(tot_out_main)} tok  '
      f'(to mianownik dla % oszczędności)')

print('\n=== 2. PROJEKTY wg output MAIN (top 20) ===')
print(f'{"proj":34} {"turns":>6} {"out_MAIN":>11} {"out_SON":>10} {"cache_rd":>12}')
rows = sorted(proj_tok.items(), key=lambda kv: kv[1]['out_main'], reverse=True)[:20]
for proj, p in rows:
    print(f'{proj[:34]:34} {p["turns"]:>6} {f(p["out_main"]):>11} {f(p["out_son"]):>10} {f(p["cr"]):>12}')

print('\n=== 3. TOOLE wg przypisanego output (MAIN cap) ===')
print(f'{"tool":16} {"calls":>7} {"out_MAIN":>11} {"out_SON":>10} {"calls_MAIN":>10}')
rows = sorted(tool_stats.items(), key=lambda kv: kv[1]['out_main'], reverse=True)
for name, t in rows:
    print(f'{str(name)[:16]:16} {t["calls"]:>7} {f(t["out_main"]):>11} {f(t["out_son"]):>10} {t["calls_main"]:>10}')

print('\n=== 4. BASH: programy (top 25 wg output MAIN-proxy) ===')
print(f'{"program":18} {"calls":>6} {"out_proxy":>11} {"#proj":>5}  projekty')
rows = sorted(bash_prog.items(), key=lambda kv: kv[1]['out'], reverse=True)[:25]
for k, e in rows:
    print(f'{str(k)[:18]:18} {e["n"]:>6} {f(e["out"]):>11} {len(e["projs"]):>5}  {",".join(sorted(e["projs"]))[:60]}')

print('\n=== 5. BASH: program+subcommand (top 30 wg output-proxy) ===')
print(f'{"prog sub":24} {"calls":>6} {"out_proxy":>11} {"#proj":>5}')
rows = sorted(bash_ps.items(), key=lambda kv: kv[1]['out'], reverse=True)[:30]
for k, e in rows:
    print(f'{str(k)[:24]:24} {e["n"]:>6} {f(e["out"]):>11} {len(e["projs"]):>5}')

print('\n=== 6. BASH: SZABLONY strukturalne (n>=3, top 40 wg output-proxy) ===')
print('   (ten sam kształt komendy z różnymi argumentami = kandydat na skrypt)')
print(f'{"calls":>5} {"out_proxy":>10} {"#proj":>5}  template')
rows = sorted([x for x in bash_tmpl.items() if x[1]['n'] >= 3],
              key=lambda kv: kv[1]['out'], reverse=True)[:40]
for k, e in rows:
    print(f'{e["n"]:>5} {f(e["out"]):>10} {len(e["projs"]):>5}  {k}')

print('\n=== 7. BASH: komendy DOKŁADNE powtarzalne (n>=4, top 30) ===')
print(f'{"calls":>5} {"out_proxy":>10} {"#proj":>5}  command')
rows = sorted([x for x in bash_exact.items() if x[1]['n'] >= 4],
              key=lambda kv: kv[1]['n'], reverse=True)[:30]
for k, e in rows:
    print(f'{e["n"]:>5} {f(e["out"]):>10} {len(e["projs"]):>5}  {k[:110]}')

print('\n=== 8. READ: re-ready tego samego pliku (top 20 wg redundancji) ===')
print(f'total Read calls: {read_total["n"]}  | przypisany output: {f(read_total["out"])} '
      f'(MAIN: {f(read_total["main"])})')
rr = sorted([(c, p) for (proj, p), c in read_files.items() for _ in [0] if c >= 3],
            key=lambda x: x[0], reverse=True)
# zbuduj listę (count, proj, path)
rr = sorted([((c), proj, pth) for (proj, pth), c in read_files.items() if c >= 3],
            key=lambda x: x[0], reverse=True)[:20]
redundant_reads = sum(c-1 for (proj, pth), c in read_files.items() if c >= 2)
print(f'redundantne re-ready (suma count-1 dla plików czytanych >=2x): {redundant_reads}')
for c, proj, pth in rr:
    print(f'  {c:>3}x  {proj[:18]:18}  {os.path.basename(pth)[:50]}')

print('\n=== 9. GREP / GLOB ===')
print(f'Grep: {grep_stats["n"]} calls, output-proxy {f(grep_stats["out"])}')
print(f'Glob: {glob_stats["n"]} calls, output-proxy {f(glob_stats["out"])}')

print('\n=== 10. SEKWENCJE: bigramy tool->tool (kolejne tury, top 20) ===')
rows = sorted(seq_bigram.items(), key=lambda kv: kv[1], reverse=True)[:20]
for (a, b), c in rows:
    print(f'  {c:>4}  {a} -> {b}')

print('\n=== 11. SEKWENCJE: bash program->program (kolejne bash, top 20) ===')
rows = sorted(bash_bigram.items(), key=lambda kv: kv[1], reverse=True)[:20]
for (a, b), c in rows:
    print(f'  {c:>4}  {a} -> {b}')

print('\n[done]')
