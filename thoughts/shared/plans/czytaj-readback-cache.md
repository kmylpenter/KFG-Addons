# Plan: czytaj read-back — natychmiastowy odczyt (pre-cache + streaming syntezy)

## Diagnoza latencji (zmierzona w sesji 2026-06-01/02)
- **Dostarczenie klawisza ≈ 3 s** (widać po pauzie VolDown = ~3 s). To podłoga
  wspólna dla adb i Shizuku — NIE transport, NIE Doze (ekran był włączony). Ten ~3 s
  zostaje na razie (prawdziwy zerowy lag wymagałby apki/serwisu dostępności — odłożone).
- **Read-back ≈ 11 s** = ~3 s klawisz + **piper syntezuje CAŁĄ wiadomość zanim zagra**
  (zmierzone: 244 znaki → 2,62 s synth, RTF 0,26; 438 znaków → ~4,7 s) + ~1-2 s
  audio-routing. Czyli dodatkowe ~8 s to SYNTEZA przed odtworzeniem, nie klawisz.
- Przetwarzanie watchera (VOLKEY→STREAM ENTER) jest natychmiastowe (log: ta sama sekunda).

## Cel
Read-back świeżych wiadomości ma być NATYCHMIASTOWY (plik już zsyntezowany), a rzadkie
pudła mają startować szybko (streaming pierwszego zdania).

## Fix 1 — Pre-cache audio ostatnich N=5 wiadomości per sesja (główny zysk)
- **Klucz:** `sha1(tekst_tury)` (stabilny niezależnie od indeksu). Katalog per sesja.
- **Lokalizacja:** Android-readable scratch (jak `_audio_scratch_dir()` w piper_stream:
  `/data/data/com.termux/files/home/.cache/czytaj/<sesja>/<hash>.wav`) — bo
  termux-media-player nie czyta ścieżek PRoot.
- **Kiedy syntezować:** hook końca tury (Stop) — po wyprodukowaniu wiadomości w sesji S
  zsyntezuj jej WAV do cache (najlepiej REUŻYJ wav z auto-read zamiast syntezować 2x;
  przekaż klucz przez env do piper_stream, niech zapisze do cache zamiast kasować temp).
- **Eviction:** po każdym dodaniu trzymaj max 5 plików per sesja (sortuj po mtime, kasuj
  najstarsze ponad 5). Plus globalny prune starych sesji (np. katalogi sesji nietknięte
  > X dni / albo limit łącznej liczby sesji). **Telefon się nie zaśmieca — twardy limit.**
- **Read-back (VolUp):** `_resolve_active_transcript()` → `turns[-n]` = tekst T'.
  `sha1(T')` → jeśli `<sesja>/<hash>.wav` istnieje → **graj wprost** (termux-media-player
  play) = ZERO syntezy. Jeśli brak → synteza na żądanie (Fix 2), po zsyntezowaniu dorzuć
  do cache.

## Fix 2 — Streaming syntezy dla pudeł (native path w piper_stream)
- Dziś native: `synthesize_one_shot(cały tekst)` → `play_blocking`. Brak streamingu.
- Zmiana: tnij tekst na ZDANIA; syntezuj+graj zdanie po zdaniu. Pierwsze zdanie gra po
  ~0,5-1 s, reszta syntezuje się w tle (RTF 0,26 → synth wyprzedza odtwarzanie, brak luk).
- Czas-do-pierwszego-dźwięku: z ~4,7 s (cała wiadomość) do ~0,7 s (pierwsze zdanie).
- **RYZYKO:** silnik audio jest WSPÓŁDZIELONY z auto-read; zachować pauzę/resume
  (_play_via_termux_blocking poll), przerwanie na _vt_recording, rezerwację kanału
  (_reserve_channel), oraz spójność per-chunk. Testować oba tory (auto + read-back).

## Kolejność wdrożenia (skupiona sesja)
1. Cache manager (zapis/lookup/eviction) + integracja read-back (Fix 1) — największy zysk,
   niższe ryzyko (read-back hit omija silnik).
2. Streaming syntezy (Fix 2) — dla pudeł; ostrożnie, testować auto-read.
3. Weryfikacja: zmierzyć read-back hit (≈ klawisz, ~3 s) i miss (pierwsze zdanie ~4 s).

## Stan wejściowy (zrobione w tej sesji)
- adb sparowane + połączone (127.0.0.1, serial w `~/.claude/czytaj-adb-serial`); split-screen
  był kluczem do parowania (okno parowania ginie przy przełączeniu aplikacji).
- volume_watcher czyta przez `adb exec-out dd` z fallbackiem na rish (`_adb_serial()`),
  ALE to NIE zmniejszyło latencji (klawisz ~3 s wspólny dla obu) — adb można zostawić
  (fallback bezpieczny) albo zrewertować jeśli upraszczamy.
- Wcześniej (commit f83333a): kolizja read-back, live-tmux targeting, globalne klawisze,
  wakelock.
