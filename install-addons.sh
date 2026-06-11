#!/usr/bin/env bash
# ============================================================
# KFG Addons Installer — wersja POSIX/bash (Termux, proot, Linux, macOS)
# Odpowiednik install-addons.ps1 dla swiatow bez PowerShella.
#
# Uzycie:
#   bash install-addons.sh              # tryb interaktywny
#   bash install-addons.sh --list       # tylko lista
#   bash install-addons.sh --all        # wszystkie pasujace do platformy
#   bash install-addons.sh --addon czytaj
#   bash install-addons.sh --all --force
#
# Cel instalacji: $CLAUDE_TARGET_BASE jesli ustawione, inaczej $HOME/.claude.
# Honoruje pole "platform" z addon.json (termux | termux+proot | any | windows).
# Postinstalle PowerShell sa POMIJANE poza Windowsem (z jawnym komunikatem).
# ============================================================
set -uo pipefail

VERSION="3.0.0-sh"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADDONS_DIR="$SCRIPT_DIR/addons"
CLAUDE_DIR="${CLAUDE_TARGET_BASE:-$HOME/.claude}"
INSTALL_HOME="$(dirname "$CLAUDE_DIR")"   # korzen dla targetow ~/ spoza .claude (np. ~/.templates); w tescie izoluje sie razem z CLAUDE_DIR

# ---- argumenty ----
MODE="interactive"; ONE_ADDON=""; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) MODE="all" ;;
    --list) MODE="list" ;;
    --force) FORCE=1 ;;
    --addon) shift; ONE_ADDON="${1:-}"; MODE="one" ;;
    --addon=*) ONE_ADDON="${1#--addon=}"; MODE="one" ;;
    -h|--help) MODE="list" ;;
    *) echo "  [!] Nieznany argument: $1" >&2 ;;
  esac
  shift
done

# ---- output ----
if [ -t 1 ]; then C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_C=$'\033[36m'; C_D=$'\033[90m'; C_0=$'\033[0m'
else C_G=""; C_Y=""; C_R=""; C_C=""; C_D=""; C_0=""; fi
ok()   { printf '    %s[OK]%s %s\n' "$C_G" "$C_0" "$1"; }
warn() { printf '    %s[!]%s %s\n'  "$C_Y" "$C_0" "$1"; }
err()  { printf '    %s[X]%s %s\n'  "$C_R" "$C_0" "$1" >&2; }
info() { printf '    %s-->%s %s\n'  "$C_C" "$C_0" "$1"; }
skip() { printf '    %s[~] %s%s\n'  "$C_D" "$1" "$C_0"; }

# ---- wykrycie hosta ----
detect_host() {
  if [ -n "${TERMUX_VERSION:-}" ] || [ "${PREFIX:-}" = "/data/data/com.termux/files/usr" ]; then echo termux; return; fi
  if [ -d /data/data/com.termux ]; then echo proot; return; fi   # proot-distro na Androidzie
  case "$(uname -s 2>/dev/null)" in Darwin) echo macos ;; *) echo linux ;; esac
}
HOST="$(detect_host)"
case "$HOST" in
  termux) HOST_TOKENS="termux any" ;;
  proot)  HOST_TOKENS="termux+proot termux proot any" ;;   # w setupie usera proot wspoldzieli ~/.claude z Termuksem
  macos)  HOST_TOKENS="macos darwin linux any" ;;
  *)      HOST_TOKENS="linux any" ;;
esac

# ---- helper: pojedyncze pole z addon.json (puste gdy brak) ----
json_field() { # $1=plik $2=klucz
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
v=d.get(sys.argv[2])
if v is None: sys.exit(0)
print(v if isinstance(v,str) else json.dumps(v))
PY
}

# ---- helper: targety jako "klucz<TAB>wartosc" ----
json_targets() { # $1=plik
  python3 - "$1" <<'PY' 2>/dev/null
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
for k,v in (d.get("targets") or {}).items():
    if isinstance(k,str) and isinstance(v,str): print(k+"\t"+v)
PY
}

# ---- helper: zaleznosci required (oba schematy: obiekt {required,minVersion} i tablica system/npm) ----
json_required_deps() { # $1=plik -> linie "name<TAB>minVersion"
  python3 - "$1" <<'PY' 2>/dev/null
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
deps=d.get("dependencies") or {}
if isinstance(deps,dict):
    for name,cfg in deps.items():
        if isinstance(cfg,dict):
            if cfg.get("required"): print(name+"\t"+str(cfg.get("minVersion","")))
        elif isinstance(cfg,list):   # schemat tablicowy: system/npm/android-apk
            for item in cfg: print(str(item)+"\t")
PY
}

# ---- platform eligibility ----
platform_ok() { # $1=platform string ("" = brak pola)
  local p="$1" t
  [ -z "$p" ] && return 0          # brak pola = traktuj jak "any" (z ostrzezeniem przy instalacji)
  [ "$p" = "any" ] && return 0
  for t in $HOST_TOKENS; do case " $p " in *"$t"*) return 0 ;; esac; done
  return 1
}

# ---- bezpieczne rozwiniecie celu: ~ -> $CLAUDE_DIR/$HOME, odrzuc traversal ----
expand_target() { # $1=target value (np. "~/.claude/skills/") -> echo absolutna sciezka albo pusto+rc1
  local v="$1" rest abs
  case "$v" in
    *..*) return 1 ;;                                   # M20/M52: zaden segment '..'
  esac
  # UWAGA: tylda w PATTERNZE ${v#...} musi byc CYTOWANA, inaczej bash rozwija ~ do $HOME
  case "$v" in
    "~/.claude/"*) rest="${v#"~/.claude/"}"; abs="$CLAUDE_DIR/$rest" ;;
    "~/.claude")   abs="$CLAUDE_DIR" ;;
    "~/"*)         rest="${v#"~/"}";         abs="$INSTALL_HOME/$rest" ;;
    "~")           abs="$INSTALL_HOME" ;;
    /*)            abs="$v" ;;
    *)             abs="$INSTALL_HOME/$v" ;;
  esac
  # normalizuj wielokrotne i koncowe slashe (skills/ -> skills, a// -> a/)
  while case "$abs" in *//*) true ;; *) false ;; esac; do abs="${abs//\/\//\/}"; done
  abs="${abs%/}"; [ -z "$abs" ] && abs="/"
  # kontrola korzenia: wynik MUSI byc pod $INSTALL_HOME (obejmuje .claude i rodzenstwo typu .templates)
  case "$abs/" in
    "$INSTALL_HOME"/*) printf '%s\n' "$abs" ;;
    *) return 1 ;;
  esac
}

# ---- atomowy zapis env do settings.json (ensureEnv) ----
ensure_env() { # $1=addon.json
  local envjson; envjson="$(json_field "$1" ensureEnv)"
  [ -z "$envjson" ] && return 0
  local settings="$CLAUDE_DIR/settings.json"
  [ -f "$settings" ] || { warn "ensureEnv: brak $settings — pomijam"; return 0; }
  python3 - "$settings" "$envjson" <<'PY' 2>/dev/null && ok "settings.json (env) zaktualizowane" || warn "ensureEnv: blad zapisu (pominieto)"
import json,sys,os,tempfile
path,envj=sys.argv[1],sys.argv[2]
try:
    d=json.load(open(path)); want=json.loads(envj)
except Exception: sys.exit(1)
if not isinstance(want,dict): sys.exit(0)
env=d.setdefault("env",{})
ch=False
for k,v in want.items():
    if env.get(k)!=v: env[k]=v; ch=True
if not ch: sys.exit(0)
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd,"w") as f: json.dump(d,f,indent=2,ensure_ascii=False)
os.replace(tmp,path)
PY
}

# ---- sprawdzenie zaleznosci (CHECK-ONLY: ostrzega, nie instaluje) ----
check_deps() { # $1=addon.json
  local line name minv
  while IFS=$'\t' read -r name minv; do
    [ -z "$name" ] && continue
    if command -v "$name" >/dev/null 2>&1; then
      ok "Zaleznosc $name OK"
    else
      case "$HOST" in
        termux) warn "Brak: $name — zainstaluj: pkg install $name" ;;
        proot|linux) warn "Brak: $name — zainstaluj: apt install $name (lub odpowiednik)" ;;
        macos) warn "Brak: $name — zainstaluj: brew install $name" ;;
      esac
    fi
  done < <(json_required_deps "$1")
}

# ---- instalacja jednego addonu ----
install_addon() { # $1=folder addonu
  local dir="$1" json="$1/addon.json"
  [ -f "$json" ] || { warn "Brak addon.json w $dir"; return 1; }

  local name disp ver platform postinstall notes
  name="$(json_field "$json" name)"
  disp="$(json_field "$json" displayName)"; [ -z "$disp" ] && disp="$name"
  ver="$(json_field "$json" version)"
  platform="$(json_field "$json" platform)"
  postinstall="$(json_field "$json" scripts | python3 -c 'import json,sys
try: print((json.load(sys.stdin) or {}).get("postinstall",""))
except Exception: pass' 2>/dev/null)"
  notes="$(json_field "$json" notes)"

  printf '\n  %sInstaluje: %s v%s%s\n' "$C_Y" "$disp" "$ver" "$C_0"

  # --- platforma ---
  if ! platform_ok "$platform"; then
    skip "Pomijam $name — platforma '$platform' != host '$HOST'"; return 0
  fi
  [ -z "$platform" ] && warn "addon.json bez pola 'platform' — zakladam 'any'"

  # --- czy postinstall to PowerShell (nie uruchomimy poza Windowsem) ---
  local ps_postinstall=0
  case "$postinstall" in powershell*|pwsh*) ps_postinstall=1 ;; esac

  # --- targety ---
  local has_targets=0
  while IFS=$'\t' read -r _ _; do has_targets=1; break; done < <(json_targets "$json")

  if [ "$has_targets" -eq 0 ] && [ "$ps_postinstall" -eq 1 ]; then
    skip "Pomijam $name — tylko postinstall PowerShell, brak plikow do skopiowania (host: $HOST)"; return 0
  fi

  check_deps "$json"

  # --- kopiowanie targetow ---
  local key val src abs destdir destfile srcname failed=0
  while IFS=$'\t' read -r key val; do
    [ -z "$key" ] && continue
    case "$key" in *..*) err "Odrzucam zrodlo z '..': $key"; failed=1; continue ;; esac
    src="$dir/$key"
    if [ ! -e "$src" ]; then warn "Brak zrodla: $key"; continue; fi

    if ! abs="$(expand_target "$val")"; then
      err "Niebezpieczny/zly cel '$val' (klucz $key) — pomijam"; failed=1; continue
    fi

    if [ -f "$src" ]; then
      # plik -> katalog docelowy to $abs jesli konczy sie '/', inaczej parent gdy val wskazuje plik
      case "$val" in
        */) destdir="$abs" ;;
        *)  if [ "$(basename "$val")" = "$(basename "$src")" ]; then destdir="$(dirname "$abs")"; else destdir="$abs"; fi ;;
      esac
      mkdir -p "$destdir" 2>/dev/null || { err "Nie moge utworzyc $destdir"; failed=1; continue; }
      destfile="$destdir/$(basename "$src")"
      if [ -f "$destfile" ] && [ "$FORCE" -eq 0 ] && [ ! "$src" -nt "$destfile" ]; then
        skip "Pomijam: $(basename "$src") (istniejacy nie starszy)"; continue
      fi
      [ -f "$destfile" ] && cp -p "$destfile" "$destfile.backup-$(date +%Y-%m-%d-%H%M)" 2>/dev/null && info "Backup: $(basename "$destfile").backup-..."
      cp -p "$src" "$destfile" && ok "Skopiowano: $key -> $destdir" || { err "Kopiowanie nieudane: $key"; failed=1; }
    else
      # katalog: cel bazowy = $abs; dopisz nazwe katalogu zrodla TYLKO jesli $abs jej jeszcze nie zawiera
      # (np. skills/ + zrodlo np -> skills/np; ale skills/eos/ + zrodlo eos -> skills/eos, bez podwojenia)
      srcname="$(basename "$src")"
      if [ "$(basename "$abs")" = "$srcname" ]; then destdir="$abs"; else destdir="$abs/$srcname"; fi
      mkdir -p "$destdir" 2>/dev/null || { err "Nie moge utworzyc $destdir"; failed=1; continue; }
      # kopiuj zawartosc (z kropkami), pomijajac __pycache__
      if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude '__pycache__' "$src"/ "$destdir"/ && ok "Skopiowano katalog: $key -> $destdir" || { err "Kopiowanie nieudane: $key"; failed=1; }
      else
        cp -a "$src"/. "$destdir"/ 2>/dev/null && { find "$destdir" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null; ok "Skopiowano katalog: $key -> $destdir"; } || { err "Kopiowanie nieudane: $key"; failed=1; }
      fi
    fi
  done < <(json_targets "$json")

  # --- ensureEnv ---
  ensure_env "$json"

  # --- postinstall ---
  if [ -n "$postinstall" ]; then
    if [ "$ps_postinstall" -eq 1 ]; then
      skip "Postinstall PowerShell pominiety (host: $HOST) — uruchom na Windowsie jesli potrzebny"
    else
      info "Uruchamiam postinstall..."
      # M2: podstaw OBA tokeny + eksportuj srodowisko (M24: wspolny korzen)
      local cmd="${postinstall//%ADDON_DIR%/$dir}"
      cmd="${cmd//\$ADDON_DIR/$dir}"
      ADDON_DIR="$dir" CLAUDE_TARGET_BASE="$CLAUDE_DIR" bash -c "$cmd"
      if [ $? -eq 0 ]; then ok "Postinstall wykonany"; else err "Postinstall ZWROCIL BLAD (addon moze nie dzialac)"; failed=1; fi
    fi
  fi

  [ -n "$notes" ] && { echo ""; info "Uwagi: $notes"; }

  if [ "$failed" -eq 0 ]; then ok "$disp zainstalowany!"; return 0
  else err "$disp zainstalowany z BLEDAMI (patrz wyzej)"; return 1; fi
}

# ---- zbierz addony ----
list_addon_dirs() { find "$ADDONS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort; }

# ---- banner ----
printf '\n  %s+-----------------------------------------------------------+%s\n' "$C_C" "$C_0"
printf '  %s|           KFG Addons Installer v%s (bash)              |%s\n' "$C_C" "$VERSION" "$C_0"
printf '  %s|           Host: %-42s|%s\n' "$C_C" "$HOST -> $CLAUDE_DIR" "$C_0"
printf '  %s+-----------------------------------------------------------+%s\n\n' "$C_C" "$C_0"

[ -d "$ADDONS_DIR" ] || { err "Brak katalogu addons: $ADDONS_DIR"; exit 1; }
mapfile -t ADDON_DIRS < <(list_addon_dirs)
[ "${#ADDON_DIRS[@]}" -gt 0 ] || { err "Nie znaleziono dodatkow w $ADDONS_DIR"; exit 1; }

# ---- tryb list ----
if [ "$MODE" = "list" ]; then
  echo "  Dostepne dodatki (host: $HOST):"; echo ""
  for d in "${ADDON_DIRS[@]}"; do
    j="$d/addon.json"; [ -f "$j" ] || continue
    nm="$(json_field "$j" name)"; dn="$(json_field "$j" displayName)"; [ -z "$dn" ] && dn="$nm"
    pf="$(json_field "$j" platform)"
    if platform_ok "$pf"; then mark="${C_C}[$nm]${C_0}"; else mark="${C_D}[$nm] (inna platforma: $pf)${C_0}"; fi
    printf '    %s %s\n' "$mark" "$dn"
  done
  echo ""; exit 0
fi

# ---- tryb one ----
if [ "$MODE" = "one" ]; then
  for d in "${ADDON_DIRS[@]}"; do
    [ "$(json_field "$d/addon.json" name)" = "$ONE_ADDON" ] && { install_addon "$d"; exit $?; }
  done
  err "Nie znaleziono dodatku: $ONE_ADDON"; exit 1
fi

# ---- tryb interactive: zbuduj menu ----
if [ "$MODE" = "interactive" ]; then
  echo "  Dostepne dodatki (host: $HOST):"; echo ""
  i=0; MENU=()
  for d in "${ADDON_DIRS[@]}"; do
    j="$d/addon.json"; [ -f "$j" ] || continue
    pf="$(json_field "$j" platform)"; platform_ok "$pf" || continue
    i=$((i+1)); MENU+=("$d")
    dn="$(json_field "$j" displayName)"; [ -z "$dn" ] && dn="$(json_field "$j" name)"
    printf '    %s[%d]%s %s\n' "$C_C" "$i" "$C_0" "$dn"
  done
  echo ""; printf '    %s[A] wszystkie   [Q] wyjdz%s\n\n' "$C_Y" "$C_0"
  printf '  Wybierz (numery po przecinku albo A): '; read -r choice
  case "$choice" in
    [Qq]*) exit 0 ;;
    [Aa]*) MODE="all" ;;
    *)
      RC=0
      IFS=','; for tok in $choice; do
        tok="$(printf '%s' "$tok" | tr -d ' ')"
        case "$tok" in (*[!0-9]*|"") warn "Pomijam '$tok'"; continue ;; esac
        idx=$((tok-1))
        [ "$idx" -ge 0 ] && [ "$idx" -lt "${#MENU[@]}" ] && { install_addon "${MENU[$idx]}" || RC=1; }
      done
      unset IFS
      exit $RC ;;
  esac
fi

# ---- tryb all ----
if [ "$MODE" = "all" ]; then
  echo "  Instaluje wszystkie pasujace do platformy..."
  RC=0
  for d in "${ADDON_DIRS[@]}"; do install_addon "$d" || RC=1; done
  echo ""
  if [ "$RC" -eq 0 ]; then ok "Wszystkie dodatki zainstalowane!"; else warn "Zakonczono z bledami w niektorych addonach (patrz wyzej)"; fi
  exit $RC
fi
