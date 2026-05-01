# Audyt addon `czytaj` - Raport końcowy

**Data:** 2026-04-28
**Tryb:** /petla audit (2 iteracje, 7 walidatorów total)
**Source state file:** `thoughts/shared/petla/audit-czytaj-2026-04-28.yaml`

---

## TL;DR

Addon `czytaj` działa, ale ma **57 problemów** z czego **9 krytycznych**. Iteracja 2 wykazała że **główna skarga użytkownika ("TTS przerywa WhatsApp") nie jest rozwiązywalna na Android 16 bez root-a** — wszystkie cztery API które mogłyby to wykryć są zablokowane przez system permissions.

**Realna droga naprawy:** zamień próbę auto-detekcji na **manualną pauzę + auto-skip gdy telefon na cichym + kolejka TTS**. To jest podejście które działa i jest deterministyczne (light-switch).

---

## Ustalenia kluczowe (po cross-validation)

### 1. WhatsApp/Messenger - niemożliwe do auto-wykrycia (Android 16 + non-root)

Walidator iteracji 2 przetestował na żywo wszystkie cztery teoretyczne mechanizmy:

| Mechanizm | Wynik testu | Powód |
|-----------|-------------|-------|
| `termux-notification-list` | **HANG >8s, EXIT=124** | Issue #621 (broken on Android 14+); user widzi popupy o uprawnienia bo coś próbuje to użyć |
| `cmd media_session list-sessions` | "***Error listing sessions***" | MEDIA_CONTENT_CONTROL = signature-only |
| `dumpsys media_session/audio/notification` | Permission Denial | DUMP permission = signature-only |
| `AudioPlaybackConfiguration` | Wymaga custom APK + redaction | MODIFY_AUDIO_ROUTING = signature |

**Wniosek:** Trzeba być uczciwym z userem - foreign-app detection jest poza zasięgiem tego addon. Próba implementacji = popupy + zwiechy + brak działania.

### 2. AC2 (PULSE_PROP_media.role=phone) - przeszacowane w iteracji 1

Iteracja 1 zaproponowała to jako "Tier-1 5-line fix". Iteracja 2 wykazała że WhatsApp **nie chodzi przez Termux PulseAudio** — używa native Android MediaSession + ExoPlayer. PA-cork pomoże tylko z apkami WEWNĄTRZ Termux (cmus/mpv/inny paplay) — czyli nie z głównym problemem usera. Downgrade z critical do minor.

### 3. AC8/L3 (code drift) - rozwiązane

md5sum potwierdził że source `_speak.py` i deployed `~/.claude/hooks/czytaj/_speak.py` są **identyczne** (ce805d09). Mic-busy SKIPs w logu były z STAREGO deploya przed 19:05 - po deploy 19:05 log jest czysty. Nie ma drift. Resolved.

### 4. Nowe critical bugs nieznalezione w iteracji 1

- **X1: VOICE_TYPER_FLAG na shared external storage** (`/storage/emulated/0/Download/Termux-flags/`) - każda apka może podrobić flag i wyciszyć czytaj, oraz każda apka widzi kiedy nagrywasz (privacy leak)
- **X2: termux-tts-speak fallback path JEST ZEPSUTY** - hangs 3s, EXIT=124. Każda awaria Piper = ciche failure. To partly tłumaczy "czasami nie działa"
- **X4: Multi-pane conflict** - jeśli używasz dwóch paneli Claude, UPS w panelu 2 zabija audio panelu 1 (pkill -f piper_stream nie filtruje po sesji)
- **X5: termux-notification-list hangs** - **dokładnie to co user właśnie zauważył w popupach!**
- **X6: install.sh wymazuje settings.json** - JSONDecodeError → s={}, kasuje hooks/permissions/env

---

## Plan naprawy w 3 priorytetach (po revision)

### Tier 1 - "User czuje różnicę natychmiast"

| # | Issue | Co zrobić |
|---|-------|-----------|
| 1 | **R1** | Retry loop na empty-turn-text (Anthropic #15813 workaround) - pierwsza przyczyna 33% SKIPów |
| 2 | **X2** | Usuń termux-tts-speak fallback ALBO dodaj install-time test który wykryje hang |
| 3 | **R2 + X3** | Skasuj `is_mic_busy()` całkowicie. Dodaj komentarz dlaczego (RECORD_AUDIO permission missing → zawsze busy=True) |
| 4 | **U1 + A1** | Wybierz JEDNĄ powierzchnię toggle: ALBO command ALBO skill, druga delete |
| 5 | **NOWY** | Manual pause flag (`~/.claude/czytaj-pause.flag`) + watcher daemon - zastąp stub `is_other_audio_playing` realną implementacją Layer-1 |
| 6 | **A8** | Re-run install.sh ALBO drop PreToolUse z install (streaming-questions to dead code) |

### Tier 2 - Code quality / correctness

| # | Issue | Co zrobić |
|---|-------|-----------|
| 7 | **R3 + A7** | Long-lived player daemon owning playback - zabij orphan chain |
| 8 | **R6** | Fix flock pattern (single coordination lock) |
| 9 | **L2** | Dodaj `_log()` do piper_server.py + capture stderr |
| 10 | **X1** | Move VOICE_TYPER_FLAG do `~/.claude/` private storage (mode 0600) |
| 11 | **X6** | install.sh hard-fail przy JSON corruption |
| 12 | **U3 + U4 + U5** | Audible toggle confirmations (light-switch UX) |

### Tier 3 - Acknowledge platform limit

| # | Issue | Co zrobić |
|---|-------|-----------|
| 13 | **AC1, AC5** | Mark wontfix-by-platform. Dodaj do README: "manualna pauza to jedyny sposób na WhatsApp" |
| 14 | **AC2** | Implementuj jako MINOR (cmus/mpv ducking only), nie jako WhatsApp solution |
| 15 | **X9** | Add install-time smoke tests (Piper round-trip, paplay, termux-tts-speak hang detection) |

---

## Konkretny plan implementacji Tier-1 (gotowy kod)

Walidator iteracji 2 przygotował drop-in kod dla nowej `is_other_audio_playing()`:

```python
# Composite skip-decision dla _speak.py
def is_paused_by_user() -> bool:
    """Manual pause flag - user controls. ~/.claude/czytaj-pause.flag"""
    try:
        with open(PAUSE_FLAG, "r") as f:
            content = f.read().strip()
    except OSError:
        return False
    if not content:
        return True  # indefinite
    try:
        expires_at = float(content)
    except ValueError:
        return True
    if time.time() >= expires_at:
        os.unlink(PAUSE_FLAG)
        return False
    return True

def is_device_silenced() -> bool:
    """termux-volume - gdy music=0 AND notification=0, telefon na cichym"""
    # ~150ms call, well under hook budget
    ...

def is_self_already_speaking() -> bool:
    """pactl list short sink-inputs - już mówimy, niech skończy"""
    ...

def is_other_audio_playing() -> bool:
    """NOT literally 'foreign audio' (impossible) - 'should I suppress this TTS?'"""
    return is_paused_by_user() or is_device_silenced() or is_self_already_speaking()
```

Plus watcher daemon (~80 LOC) który drainuje queue gdy pauza wygaśnie.

Pełny kod w state file: `audit-czytaj-2026-04-28.yaml` sekcja `RECOMMENDED_IMPLEMENTATION`.

---

## Obserwacja użytkownika z dziś (popupy "Termux:API chciałoby mieć dostęp do powiadomień")

**Bezpośrednie potwierdzenie X5:** ten popup to dokładnie objaw tego że COŚ próbuje aktywować Notification Listener Service. Sprawdziłem - **nasz addon czytaj NIE używa termux-notification-list nigdzie**. Te popupy pochodzą od innej apki (prawdopodobnie Voice Typer lub inna z twoich apk korzystających Termux:API).

**Wniosek dla audytu:** to wzmacnia rekomendację - **NIE dodawaj termux-notification-list jako detection w czytaj**. Spowodowałoby to jeszcze więcej takich popupów + i tak nie działa (issue #621).

---

## Statystyki audytu

- **57 issues** found across 5 lenses + cross-validation
- **9 critical** (po revision: 7 critical actionable)
- **28 major**
- **18 minor**
- **3 resolved/wontfix-by-platform** (AC8, L3, AC1/AC5)
- **2 lenses zmieniły klasyfikacje**: AC2 critical→minor, AC1/AC5 → wontfix-by-platform
- **6 nowych issues z iteracji 2**: X1-X9

## Następny krok

User decyduje czy przechodzimy do `/petla solve` (naprawić wszystko z planu Tier-1+2+3) czy do `/petla solve --tier-1-only` (tylko 6 najwyższych priorytetów).

Source files:
- `thoughts/shared/petla/audit-czytaj-2026-04-28.yaml` (full issue list with research links)
- `thoughts/shared/petla/audit-czytaj-2026-04-28-FINAL-REPORT.md` (this file)
