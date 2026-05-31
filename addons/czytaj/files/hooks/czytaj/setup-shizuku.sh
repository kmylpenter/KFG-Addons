#!/data/data/com.termux/files/usr/bin/bash
# czytaj — Shizuku integration setup (one-time).
# Extracts the rish binary from the installed Shizuku APK and registers
# it in Termux PATH. After this, czytaj's _speak.py can call rish to
# query dumpsys window (screen lock), dumpsys audio (mic activity), and
# cmd media_session (foreign media playback) — all with shell uid, NO
# root, NO Wireless Debugging pairing required.
#
# Prerequisite: Shizuku APK installed AND service activated by user
# inside the Shizuku app (Settings → Service is running).

set -e

PKG=moe.shizuku.privileged.api
RISH_HOME="$HOME/.shizuku"
RISH_BIN="$PREFIX/bin/rish"
FLAG="$HOME/.claude/czytaj-shizuku.flag"

echo ""
echo "==> czytaj — Shizuku setup"
echo ""

# --- Locate Shizuku APK ---
APK=$(pm path "$PKG" 2>/dev/null | head -1 | cut -d: -f2)
if [ -z "$APK" ] || [ ! -r "$APK" ]; then
  echo "  [X] Shizuku APK ($PKG) nie zainstalowane lub APK nieczytalne."
  echo "      Zainstaluj Shizuku z F-Droid lub Google Play, potem aktywuj."
  exit 1
fi
echo "  [OK] Shizuku APK: $APK"

# --- Extract rish ---
mkdir -p "$RISH_HOME"
chmod 700 "$RISH_HOME"
( cd "$RISH_HOME" && unzip -o -j -q "$APK" \
    'assets/rish' \
    'assets/rish_shizuku.dex' \
    'lib/arm64-v8a/librish.so' )
chmod 400 "$RISH_HOME/rish_shizuku.dex"  # Android 14+ refuses writable dex
chmod 755 "$RISH_HOME/rish"
echo "  [OK] rish wypakowane do $RISH_HOME"

# --- Wrapper that sets RISH_APPLICATION_ID for Termux ---
cat > "$RISH_HOME/rish-wrapper.sh" <<'WRAP'
#!/data/data/com.termux/files/usr/bin/bash
export RISH_APPLICATION_ID=com.termux
exec "$HOME/.shizuku/rish" "$@"
WRAP
chmod 755 "$RISH_HOME/rish-wrapper.sh"

# --- Install wrapper as `rish` in PATH ---
ln -sf "$RISH_HOME/rish-wrapper.sh" "$RISH_BIN"
echo "  [OK] rish symlink w PATH: $RISH_BIN"

# --- Smoke test ---
echo ""
echo "Test: czy Shizuku odpowiada?"
if ID_OUT=$("$RISH_BIN" -c "id" 2>&1) && echo "$ID_OUT" | grep -q "uid=2000"; then
  echo "  [OK] uid=shell — Shizuku aktywne i odpowiada."
else
  echo "  [X] rish nie zwraca uid shell."
  echo "      Output: $ID_OUT"
  echo ""
  echo "  Najczęstsza przyczyna: Shizuku NIE jest aktywne."
  echo "  Otwórz apkę Shizuku i upewnij się, że widzisz 'Service is running'."
  exit 1
fi

# --- Test required dumpsys endpoints ---
echo ""
echo "Test endpointów potrzebnych dla czytaj:"

if "$RISH_BIN" -c "dumpsys window | grep -q mDreamingLockscreen" 2>/dev/null; then
  echo "  [OK] dumpsys window — detekcja blokady ekranu"
else
  echo "  [!] dumpsys window niedostępne — detekcja blokady wyłączona"
fi

if "$RISH_BIN" -c "dumpsys audio | head -1" >/dev/null 2>&1; then
  echo "  [OK] dumpsys audio — detekcja nagrywania mikrofonu"
else
  echo "  [!] dumpsys audio niedostępne — mic detekcja wyłączona"
fi

if "$RISH_BIN" -c "cmd media_session list-sessions" >/dev/null 2>&1; then
  echo "  [OK] cmd media_session — detekcja WhatsApp/Spotify/itd."
else
  echo "  [!] cmd media_session niedostępne"
fi

# --- Sentinel flag: signal to _speak.py that rish is available ---
echo "ready" > "$FLAG"
chmod 600 "$FLAG"

cat <<EOF

==> Gotowe. Shizuku zintegrowane z czytaj.
  Sentinel:  $FLAG
  rish bin:  $RISH_BIN

Co teraz działa:
  - Detekcja zablokowanego ekranu (TTS milknie w kieszeni)
  - Detekcja nagrywania mikrofonu (nie gada gdy nagrywasz głosówkę)
  - Detekcja WhatsApp/Spotify (nie gada gdy gra inna apka)

Aby WYŁĄCZYĆ rish detection:
  rm $FLAG

EOF
