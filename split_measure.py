#!/usr/bin/env python3
"""Zmierz realny wzorzec dostępu do Code.gs i index.html w oknie 7 dni.
Decyduje, ile DA split: pełne dumpy (cat/paginacja) -> split oszczędza dużo;
already-targeted (offset/limit) -> split oszczędza mało."""
import os, re, json
from datetime import datetime, timezone, timedelta
from collections import defaultdict

ROOT=os.path.expanduser('~/.claude/projects')
NOW=datetime.now(timezone.utc); CUT=NOW-timedelta(days=7)
FLOOR=(NOW-timedelta(days=8)).timestamp()

def pts(ts):
    try: return datetime.fromisoformat(ts.replace('Z','+00:00'))
    except: return None

def is_target(p):
    if not p: return None
    b=os.path.basename(p)
    return p if b in ('Code.gs','index.html') else None

reads=defaultdict(lambda: dict(n=0, full=0, off=0, limits=[], offsets=[]))
bash=defaultdict(lambda: dict(cat=0, grep=0, sed=0, headtail=0, wc=0, node=0, other=0))
paths=set()

for dp,_,files in os.walk(ROOT):
    for fn in files:
        if not fn.endswith('.jsonl'): continue
        fp=os.path.join(dp,fn)
        try:
            if os.path.getmtime(fp)<FLOOR: continue
        except OSError: continue
        for line in open(fp,errors='replace'):
            if 'Code.gs' not in line and 'index.html' not in line: continue
            if '"assistant"' not in line: continue
            try: o=json.loads(line)
            except: continue
            if o.get('type')!='assistant': continue
            ts=pts(o.get('timestamp'))
            if ts and ts<CUT: continue
            cont=(o.get('message') or {}).get('content')
            if not isinstance(cont,list): continue
            for b in cont:
                if not isinstance(b,dict) or b.get('type')!='tool_use': continue
                name=b.get('name'); inp=b.get('input') or {}
                if name=='Read':
                    p=is_target(inp.get('file_path'))
                    if p:
                        paths.add(p); r=reads[p]; r['n']+=1
                        off=inp.get('offset'); lim=inp.get('limit')
                        if off is None and lim is None: r['full']+=1
                        else:
                            r['off']+=1
                            if lim is not None: r['limits'].append(lim)
                            if off is not None: r['offsets'].append(off)
                elif name=='Bash':
                    cmd=inp.get('command','') or ''
                    for tgt in ('Code.gs','index.html'):
                        if tgt not in cmd: continue
                        if re.search(r'\bcat\b\s+[^|;&]*'+re.escape(tgt), cmd): bash[tgt]['cat']+=1
                        elif 'grep' in cmd: bash[tgt]['grep']+=1
                        elif 'sed' in cmd: bash[tgt]['sed']+=1
                        elif re.search(r'\b(head|tail)\b', cmd): bash[tgt]['headtail']+=1
                        elif 'wc' in cmd: bash[tgt]['wc']+=1
                        elif 'node' in cmd: bash[tgt]['node']+=1
                        else: bash[tgt]['other']+=1

def meta(p):
    try:
        d=open(p,errors='replace').read()
        l=d.count('\n')+1; t=len(d)//4
        return l, t, (t/l if l else 0)
    except OSError: return None

print("="*64)
print("WZORZEC DOSTĘPU do Code.gs / index.html (okno 7d)")
print("Read tool: domyślnie max 2000 linii (full-default ≠ cały plik)")
print("="*64)
tot_read_tok=0
for p in sorted(paths):
    m=meta(p); r=reads[p]
    if not m:
        print(f"\n{p}\n   (plik nieobecny — nie zmierzę rozmiaru)"); continue
    l,t,tpl=m
    cap=min(2000,l)
    full_tok=r['full']*cap*tpl
    off_tok=sum(min(x,l)*tpl for x in r['limits'])+(r['off']-len(r['limits']))*cap*tpl
    tot_read_tok+=full_tok+off_tok
    print(f"\n{p.replace(os.path.expanduser('~'),'~')}")
    print(f"   ROZMIAR: {l} linii / ~{t/1000:.0f}k tok ({tpl:.0f} tok/linia)")
    print(f"   Read: {r['n']}  | full-default(≤2000l, ~{cap*tpl/1000:.0f}k tok): {r['full']}  | offset/limit: {r['off']}")
    if r['limits']:
        import statistics
        print(f"     limity linii: min={min(r['limits'])} med={int(statistics.median(r['limits']))} max={max(r['limits'])}")
    print(f"   est. tokeny zaczytane Read-em (7d): full~{full_tok/1000:.0f}k + offset~{off_tok/1000:.0f}k = ~{(full_tok+off_tok)/1000:.0f}k")

print("\n=== BASH dostęp (cat=pełny dump pliku; grep/sed/head=częściowy) ===")
for tgt,d in sorted(bash.items()):
    nz={k:v for k,v in d.items() if v}
    print(f"  {tgt}: {nz}")
print(f"\nSUMA est. tokenów zaczytanych Read-em dla obu plików (7d): ~{tot_read_tok/1000:.0f}k")
