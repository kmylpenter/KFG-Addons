#!/usr/bin/env python3
"""env-doctor postinstall — merge do ~/.claude/settings.json w trybie ADD-IF-ABSENT.

Celowo NIE uzywa ensureEnv instalatora: ensureEnv WYMUSZA wartosci, a te ustawienia
sa per-urzadzenie (desktop z postgresem ma miec wlasne; niczego nie nadpisujemy).

1. env: EMBEDDING_PROVIDER=mock + AGENTICA_MEMORY_BACKEND=sqlite — tylko gdy klucza
   nie ma I nie ma DATABASE_URL/CONTINUOUS_CLAUDE_DB_URL (maszyna postgresowa = pomin).
   CLAUDE_OPC_DIR=<~/.claude> — tylko gdy brak.
2. hooks.PostToolUse: wpis {matcher: "Grep" -> node .../epistemic-reminder.mjs}
   — tylko gdy zaden istniejacy wpis nie wola epistemic-reminder.
Zapis atomowy (tempfile + replace). Idempotentny.
"""

import json
import os
import sys
import tempfile

CLAUDE_DIR = os.path.expanduser("~/.claude")
SETTINGS = os.path.join(CLAUDE_DIR, "settings.json")
HOOK_PATH = os.path.join(CLAUDE_DIR, "hooks", "dist", "epistemic-reminder.mjs")


def main() -> int:
    if not os.path.isfile(SETTINGS):
        print(f"env-doctor postinstall: brak {SETTINGS} — pomijam merge (uruchom Claude raz i zainstaluj ponownie)")
        return 0
    try:
        with open(SETTINGS, encoding="utf-8") as f:
            settings = json.load(f)
    except Exception as e:
        print(f"env-doctor postinstall: settings.json nieczytelny ({e}) — NIE dotykam pliku")
        return 1

    changed = []

    env = settings.setdefault("env", {})
    pg_mode = bool(env.get("DATABASE_URL") or env.get("CONTINUOUS_CLAUDE_DB_URL")
                   or os.environ.get("DATABASE_URL") or os.environ.get("CONTINUOUS_CLAUDE_DB_URL"))
    if pg_mode:
        print("env-doctor: wykryto DATABASE_URL (postgres) — pomijam domyslne sqlite/mock")
    else:
        for k, v in (("EMBEDDING_PROVIDER", "mock"), ("AGENTICA_MEMORY_BACKEND", "sqlite")):
            if k not in env:
                env[k] = v
                changed.append(f"env.{k}={v}")
    if "CLAUDE_OPC_DIR" not in env and os.path.isdir(os.path.join(CLAUDE_DIR, "scripts", "core")):
        env["CLAUDE_OPC_DIR"] = CLAUDE_DIR
        changed.append(f"env.CLAUDE_OPC_DIR={CLAUDE_DIR}")

    hooks = settings.setdefault("hooks", {})
    post = hooks.setdefault("PostToolUse", [])
    already = any(
        "epistemic-reminder" in (h.get("command") or "")
        for entry in post if isinstance(entry, dict)
        for h in (entry.get("hooks") or []) if isinstance(h, dict)
    )
    if already:
        print("env-doctor: hook epistemic-reminder juz podpiety — pomijam")
    elif not os.path.isfile(HOOK_PATH):
        print(f"env-doctor: brak {HOOK_PATH} — wpisu hooka nie dodaje")
    else:
        # sciezka absolutna per-urzadzenie: $HOME w komendzie nie rozwija sie na Windowsie
        post.insert(0, {
            "matcher": "Grep",
            "hooks": [{"type": "command", "command": f'node "{HOOK_PATH}"', "timeout": 5}],
        })
        changed.append("hooks.PostToolUse[Grep] -> epistemic-reminder.mjs")

    if not changed:
        print("env-doctor postinstall: nic do zmiany (idempotentny no-op)")
        return 0

    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(SETTINGS))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(settings, f, indent=2, ensure_ascii=False)
            f.write("\n")
        os.replace(tmp, SETTINGS)
    except Exception as e:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        print(f"env-doctor postinstall: zapis nieudany ({e}) — settings.json nietkniety")
        return 1

    print("env-doctor postinstall: zaktualizowano: " + "; ".join(changed))
    print("UWAGA: nowy hook/env zadziala od NASTEPNEJ sesji Claude (konfiguracja laduje sie na starcie).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
