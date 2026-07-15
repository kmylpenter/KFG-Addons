#!/usr/bin/env python3
"""noc_ssot.py — mechaniczny rdzen TRYBU NOCNEGO skilla ssot-dry-audit (petla-noc modul S).

Podzial odpowiedzialnosci: MODEL (sesja nocna) robi osad — discovery kandydatow,
lineage, klasa (PEWNE/PRAWDOPODOBNE/RACZEJ_NIE) — i zapisuje candidates.json.
TEN SKRYPT robi cala ksiegowosc DETERMINISTYCZNIE:
  1. odrzuca RACZEJ_NIE (nigdy nie trafia do Kamila),
  2. waliduje umiejscowienie frontendowe -> DEGRADACJA o klase przy braku kompletu
     (PEWNE->PRAWDOPODOBNE; PRAWDOPODOBNE->odpada) — Kamil zna frontend, nie backend,
  3. fingerprint = sha1(zrodlo + "|" + posortowane UNIKALNE PLIKI lokalizacji)
     (poziom plikow, nie linii — stabilny na dryf numerow linii),
  4. dedup wzgledem ledgera: reported-niezmienione -> stlumione (repeat);
     approved/rejected/wontfix -> TERMINALNIE stlumione,
  5. limit znalezisk per bieg (PEWNE przodem); ponad limit -> NIE wchodzi do ledgera,
     wiec wraca w nastepnym cyklu,
  6. zapis kolejki zatwierdzen findings-<data>.yaml + ledger.yaml (JSON == poprawny
     YAML; pliki edytowac WYLACZNIE tym skryptem / narzedziami JSON-aware),
  7. sekcja do raportu porannego na stdout.

BEZPIECZNIK KOLEJKI (load-bearing): kazdy wpis kolejki ma confidence: LOW +
user_question + night_queue: awaiting_kamil -> /petla solve go POMIJA. Dopiero
dzienna sesja (AUQ nad kolejka) przepisuje zatwierdzone na HIGH + user_decision +
refactor{} i aktualizuje ledger (--set-status). Noc NIGDY nie produkuje
auto-fixowalnego YAML.

Uzycie:
  noc_ssot.py --candidates c.json [--ssot-dir .petla-noc/ssot] [--limit 12] [--date YYYY-MM-DD]
  noc_ssot.py --ssot-dir DIR --set-status FINGERPRINT approved|rejected|wontfix
  noc_ssot.py --selftest
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import os
import sys

KLASY = ("PEWNE", "PRAWDOPODOBNE", "RACZEJ_NIE")
TERMINAL = ("approved", "rejected", "wontfix")
SEVERITY = {"PEWNE": "critical", "PRAWDOPODOBNE": "major"}


def _atomic_write(path: str, text: str) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)


def _load_json(path: str, default):
    if not os.path.exists(path):
        return default
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def fingerprint(zrodlo: str, locations: list) -> str:
    files = sorted({str(l.get("file", "")) for l in locations})
    return hashlib.sha1((str(zrodlo) + "|" + ",".join(files)).encode("utf-8")).hexdigest()


def _placement_complete(c: dict) -> bool:
    u = c.get("umiejscowienie") or {}
    if not all(str(u.get(k, "")).strip() for k in ("aplikacja", "ekran", "etykieta")):
        return False
    locs = c.get("locations") or []
    if len(locs) < 2:
        return False
    return all(str(l.get("file", "")).strip() and l.get("line") for l in locs)


def _default_question(c: dict) -> str:
    u = c.get("umiejscowienie") or {}
    gdzie = " / ".join(str(u.get(k, "?")) for k in ("aplikacja", "ekran", "etykieta"))
    co = c.get("co_z_czym") or c.get("description") or "te lokalizacje"
    return (f"Czy {gdzie} oraz {co} pokazuja TE SAMA dane i powinny czytac"
            f" jedno zrodlo ({c.get('zrodlo', '?')})?")


def process(candidates: list, ledger: dict, date: str, limit: int) -> dict:
    """Czysta logika (testowalna): zwraca queue/ledger/stats. Nie dotyka dysku."""
    stats = {"wejscie": len(candidates), "raczej_nie": 0, "zdegradowane": 0,
             "odrzucone_degradacja": 0, "stlumione_repeat": 0,
             "stlumione_terminal": 0, "ponad_limit": 0}
    fresh = []
    for c in candidates:
        klasa = c.get("klasa")
        if klasa not in KLASY:
            raise ValueError(f"kandydat bez poprawnej klasy: {c.get('id', c)!r}")
        if klasa == "RACZEJ_NIE":
            stats["raczej_nie"] += 1
            continue
        c = dict(c)
        c["degraded_from"] = None
        if not _placement_complete(c):
            if klasa == "PEWNE":
                stats["zdegradowane"] += 1
                c["degraded_from"] = "PEWNE"
                c["klasa"] = klasa = "PRAWDOPODOBNE"
            else:
                stats["odrzucone_degradacja"] += 1
                continue
        else:
            c["klasa"] = klasa
        fp = fingerprint(c.get("zrodlo", ""), c.get("locations") or [])
        c["fingerprint"] = fp
        entry = ledger.get(fp)
        if entry:
            entry["last_seen"] = date
            if entry.get("status") in TERMINAL:
                stats["stlumione_terminal"] += 1
            else:
                stats["stlumione_repeat"] += 1
            continue
        fresh.append(c)
    fresh.sort(key=lambda c: (0 if c["klasa"] == "PEWNE" else 1, c["fingerprint"]))
    queue, overflow = fresh[:limit], fresh[limit:]
    stats["ponad_limit"] = len(overflow)  # NIE do ledgera -> wroci w kolejnym cyklu
    findings = []
    for c in queue:
        fp = c["fingerprint"]
        ledger[fp] = {"status": "reported", "first_seen": date, "last_seen": date,
                      "klasa": c["klasa"], "zrodlo": c.get("zrodlo", ""),
                      "files": sorted({str(l.get("file", "")) for l in c.get("locations") or []}),
                      "decided_at": None}
        findings.append({
            "id": c.get("id") or f"S-{fp[:8]}",
            "severity": SEVERITY[c["klasa"]],
            "confidence": "LOW",                 # bezpiecznik: solve POMIJA az do decyzji
            "night_queue": "awaiting_kamil",
            "type": "displayed_data_ssot",
            "klasa": c["klasa"],
            "degraded_from": c["degraded_from"],
            "zrodlo": c.get("zrodlo", ""),
            "lineage": c.get("lineage", ""),
            "umiejscowienie": c.get("umiejscowienie") or {},
            "co_z_czym": c.get("co_z_czym", ""),
            "locations": c.get("locations") or [],
            "description": c.get("description", ""),
            "fingerprint": fp,
            "user_question": c.get("user_question") or _default_question(c),
        })
    return {"findings": findings, "ledger": ledger, "stats": stats}


def _findings_doc(findings: list, date: str, scope: str, stats: dict) -> dict:
    pewne = sum(1 for f in findings if f["klasa"] == "PEWNE")
    return {
        "_comment": ("Kolejka zatwierdzen trybu nocnego audytssot (petla-noc modul S). "
                     "JSON == poprawny YAML. Wpisy sa INERTNE dla /petla solve "
                     "(confidence: LOW) do czasu decyzji Kamila w sesji dziennej."),
        "schema_version": "1.0",
        "night_mode": True,
        "audit_date": date,
        "scope": scope,
        "counts": {"total": len(findings), "critical": pewne,
                   "major": len(findings) - pewne, "minor": 0},
        "stats": stats,
        "findings": findings,
        "petla_solve_rules": {
            "HIGH": "auto_fix",
            "MEDIUM": "auto_fix_with_review_tag",
            "LOW": "skip",
            "branch": f"refactor/ssot-noc-{date}",
            "preflight": {"require_clean_tree": True},
        },
    }


def _report_section(findings: list, stats: dict, date: str, out_path: str) -> str:
    lines = [f"### S — audyt SSOT wyswietlanych danych ({date})"]
    pewne = [f for f in findings if f["klasa"] == "PEWNE"]
    prawd = [f for f in findings if f["klasa"] == "PRAWDOPODOBNE"]
    if findings:
        lines.append(f"- kolejka zatwierdzen: PEWNE {len(pewne)}, PRAWDOPODOBNE {len(prawd)} -> {out_path}")
    else:
        lines.append("- kolejka zatwierdzen: PUSTA (nic nowego wzgledem ledgera)")
    lines.append(
        f"- stlumione ledgerem: {stats['stlumione_repeat']} repeat + {stats['stlumione_terminal']} terminalne"
        f" | zdegradowane: {stats['zdegradowane']} | odrzucone: {stats['raczej_nie']} RACZEJ_NIE"
        f" + {stats['odrzucone_degradacja']} degradacja | ponad limit: {stats['ponad_limit']} (wroci)")
    if findings:
        lines.append("- decyzje: sesja dzienna -> AUQ nad kolejka -> noc_ssot.py --set-status <fp>"
                     " approved|rejected|wontfix -> /petla solve na zatwierdzonych")
    if pewne:
        lines.append("**PEWNE (do zatwierdzenia hurtem):**")
        for f in pewne:
            u = f["umiejscowienie"]
            gdzie = " / ".join(str(u.get(k, "?")) for k in ("aplikacja", "ekran", "etykieta"))
            deg = " [degradacja z PEWNE]" if f["degraded_from"] else ""
            lines.append(f"- [{f['fingerprint'][:8]}] {gdzie} — {f['co_z_czym'] or f['description']}"
                         f" (zrodlo: {f['zrodlo']}){deg}")
    if prawd:
        lines.append("**PRAWDOPODOBNE (pytania, pojedynczo):**")
        for f in prawd:
            deg = " [degradacja z PEWNE]" if f["degraded_from"] else ""
            lines.append(f"- [{f['fingerprint'][:8]}]{deg} {f['user_question']}")
    return "\n".join(lines)


def run(candidates_path: str, ssot_dir: str, date: str, limit: int, scope: str) -> int:
    os.makedirs(ssot_dir, exist_ok=True)
    raw = _load_json(candidates_path, None)
    if raw is None:
        print(f"noc_ssot: brak pliku kandydatow: {candidates_path}", file=sys.stderr)
        return 2
    candidates = raw.get("candidates") if isinstance(raw, dict) else raw
    if not isinstance(candidates, list):
        print("noc_ssot: candidates.json ma byc lista lub {'candidates': [...]}", file=sys.stderr)
        return 2
    ledger_path = os.path.join(ssot_dir, "ledger.yaml")
    ledger = _load_json(ledger_path, {})
    result = process(candidates, ledger, date, limit)
    out_path = os.path.join(ssot_dir, f"findings-{date}.yaml")
    doc = _findings_doc(result["findings"], date, scope, result["stats"])
    _atomic_write(out_path, json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
    _atomic_write(ledger_path, json.dumps(result["ledger"], ensure_ascii=False, indent=2) + "\n")
    print(_report_section(result["findings"], result["stats"], date, out_path))
    return 0


def set_status(ssot_dir: str, fp: str, status: str, date: str) -> int:
    if status not in TERMINAL + ("reported",):
        print(f"noc_ssot: status musi byc jednym z {TERMINAL + ('reported',)}", file=sys.stderr)
        return 2
    ledger_path = os.path.join(ssot_dir, "ledger.yaml")
    ledger = _load_json(ledger_path, {})
    hits = [k for k in ledger if k == fp or k.startswith(fp)]
    if len(hits) != 1:
        print(f"noc_ssot: fingerprint '{fp}' pasuje do {len(hits)} wpisow (wymagany dokladnie 1)",
              file=sys.stderr)
        return 2
    ledger[hits[0]]["status"] = status
    ledger[hits[0]]["decided_at"] = date
    _atomic_write(ledger_path, json.dumps(ledger, ensure_ascii=False, indent=2) + "\n")
    print(f"noc_ssot: {hits[0][:12]} -> {status}")
    return 0


# ---------------------------------------------------------------- selftest
def _cand(id_, klasa, zrodlo, files, complete=True):
    u = {"aplikacja": "Terminator", "ekran": "Umowy", "etykieta": "Deal name"}
    if not complete:
        u = {"aplikacja": "Terminator", "ekran": "Umowy", "etykieta": ""}
    return {"id": id_, "klasa": klasa, "zrodlo": zrodlo,
            "lineage": "getDeal() -> render", "umiejscowienie": u,
            "co_z_czym": "Umowy vs Podglad",
            "locations": [{"file": f, "line": 10 + i, "evidence": "x"} for i, f in enumerate(files)],
            "description": f"dana {zrodlo} w {len(files)} miejscach"}


def selftest() -> int:
    ok = 0

    def check(name, cond):
        nonlocal ok
        if not cond:
            print(f"SELFTEST FAIL: {name}")
            sys.exit(1)
        ok += 1
        print(f"  PASS {name}")

    d = "2026-07-15"
    c_ok = _cand("A", "PEWNE", "zoho:Deal_Name", ["a.html", "b.html"])
    c_deg = _cand("B", "PEWNE", "zoho:Amount", ["a.html", "c.html"], complete=False)
    c_drop = _cand("C", "PRAWDOPODOBNE", "store:x", ["a.html", "d.html"], complete=False)
    c_rn = _cand("D", "RACZEJ_NIE", "sheet:S!A", ["a.html", "e.html"])

    ledger: dict = {}
    r1 = process([c_ok, c_deg, c_drop, c_rn], ledger, d, 12)
    q1 = {f["id"]: f for f in r1["findings"]}
    check("PEWNE kompletne w kolejce jako PEWNE/critical", q1["A"]["klasa"] == "PEWNE" and q1["A"]["severity"] == "critical")
    check("kolejka inertna dla solve (LOW + night_queue)", all(f["confidence"] == "LOW" and f["night_queue"] == "awaiting_kamil" for f in r1["findings"]))
    check("KONTRFAKTYK: PEWNE bez etykiety ZDEGRADOWANE", q1["B"]["klasa"] == "PRAWDOPODOBNE" and q1["B"]["degraded_from"] == "PEWNE")
    check("PRAWDOPODOBNE bez kompletu ODPADA", "C" not in q1 and r1["stats"]["odrzucone_degradacja"] == 1)
    check("RACZEJ_NIE nigdy do Kamila", "D" not in q1 and r1["stats"]["raczej_nie"] == 1)
    check("ledger dostal tylko kolejke (2 wpisy reported)", len(ledger) == 2 and all(v["status"] == "reported" for v in ledger.values()))

    r2 = process([c_ok, c_deg], ledger, "2026-07-22", 12)
    check("DEDUP: drugi bieg nie re-raportuje niezmienionego", not r2["findings"] and r2["stats"]["stlumione_repeat"] == 2)
    check("dedup uaktualnia last_seen", all(v["last_seen"] == "2026-07-22" for v in ledger.values()))

    fpA = q1["A"]["fingerprint"]
    ledger[fpA]["status"] = "rejected"; ledger[fpA]["decided_at"] = "2026-07-22"
    c_ok_lines = json.loads(json.dumps(c_ok))
    for loc in c_ok_lines["locations"]:
        loc["line"] += 500  # dryf linii, te same pliki
    r3 = process([c_ok_lines], ledger, "2026-07-29", 12)
    check("TERMINAL: rejected tlumi mimo dryfu linii (fp na plikach)", not r3["findings"] and r3["stats"]["stlumione_terminal"] == 1)

    c_ok_newfile = json.loads(json.dumps(c_ok))
    c_ok_newfile["locations"].append({"file": "z.html", "line": 7, "evidence": "x"})
    r4 = process([c_ok_newfile], ledger, "2026-07-29", 12)
    check("ZMIANA (nowy plik) -> nowy fingerprint -> re-raport", len(r4["findings"]) == 1 and r4["findings"][0]["fingerprint"] != fpA)

    ledger2: dict = {}
    trio = [_cand(i, "PEWNE", f"zoho:F{i}", [f"{i}a.html", f"{i}b.html"]) for i in "XYZ"]
    r5 = process(trio, ledger2, d, 2)
    check("LIMIT: 3 swieze przy limicie 2 -> 2 w kolejce", len(r5["findings"]) == 2 and r5["stats"]["ponad_limit"] == 1)
    check("ponad limit NIE wchodzi do ledgera", len(ledger2) == 2)
    r6 = process(trio, ledger2, "2026-07-22", 2)
    check("ponad-limit WRACA w kolejnym cyklu", len(r6["findings"]) == 1 and r6["stats"]["stlumione_repeat"] == 2)

    doc = _findings_doc(r1["findings"], d, ".", r1["stats"])
    check("format zgodny z .ssot-findings.yaml (findings + petla_solve_rules)",
          "findings" in doc and "petla_solve_rules" in doc and doc["petla_solve_rules"]["LOW"] == "skip")
    check("JSON round-trip (plik == poprawny YAML)", json.loads(json.dumps(doc))["night_mode"] is True)

    print(f"SELFTEST: {ok}/{ok} PASS")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--candidates", metavar="FILE")
    p.add_argument("--ssot-dir", default=".petla-noc/ssot")
    p.add_argument("--date", default=_dt.date.today().isoformat())
    p.add_argument("--limit", type=int, default=12)
    p.add_argument("--scope", default=".")
    p.add_argument("--set-status", nargs=2, metavar=("FINGERPRINT", "STATUS"))
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args(argv)
    if a.selftest:
        return selftest()
    if a.set_status:
        return set_status(a.ssot_dir, a.set_status[0], a.set_status[1], a.date)
    if a.candidates:
        return run(a.candidates, a.ssot_dir, a.date, a.limit, a.scope)
    p.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
