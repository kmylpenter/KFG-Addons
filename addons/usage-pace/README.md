# usage-pace — monitor tempa zużycia limitów Claude Max 20x

Pilnuje, czy tempo zużycia limitu **tygodniowego (7d)** jest na ścieżce do pełnego
wykorzystania. Gdy projekcja jest za niska — **powiadomienie systemowe** z sugestią
ręcznego odpalenia sesji autonomicznej (np. `petla-noc`).

**System WYŁĄCZNIE informuje. Nigdy sam nie uruchamia żadnych sesji.**

## Co widać na ekranie

Segment dopisany na końcu pierwszej linii istniejącego paska statusu:

```
37% │ C5/1M │ MAX │ KFG-Addons
5h:17%→55% 7d:25%→30%⚠
```

(osobna linijka pod główną — wąski ekran telefonu)

- `5h:17%→55%` — zużycie okna 5-godzinnego + projekcja informacyjna
  (przyciemniona, bez alarmów; znika w pierwszych 30 min okna)
- `7d:25%` — zużycie okna tygodniowego
- `→30%` — projekcja: ile % limitu tygodniowego wykorzystam przy obecnym tempie
  - zielona = OK, **czerwona z ⚠ = za wolno (LOW)**
  - `→·` = świeże okno (mniej niż 12 h po resecie, za mało danych)
  - `→?` = dane przeterminowane (np. brak internetu) — zero alarmów
- brak segmentu = brak danych (zachowanie jak przed instalacją)

Powiadomienie (Termux, max 1 na 6 h):
> **Claude: niskie tempo zużycia**
> Projekcja: 30% limitu 7d, reset za 28 h (zostało 75%). Odpal sesję autonomiczną (np. petla-noc).

## Architektura

```
                    ┌──────────────── JEDEN WSPÓLNY CACHE ────────────────┐
                    │            ~/.claude/usage-cache.json               │
                    │      (zapis atomowy tmp+rename, TTL 300 s)          │
                    └──────────────────────────────────────────────────────┘
                        ▲  zapis (za darmo,           ▲  zapis (fetch z API,
                        │  ze stdin Claude Code)      │  tylko gdy cache stary)
   ┌────────────────────┴────────┐      ┌─────────────┴──────────────────┐
   │ statusline-wrapper.mjs      │      │ pace.sh --scheduled            │
   │ (proot, każde odświeżenie   │      │ (Termux, termux-job-scheduler  │
   │  paska; ZERO sieci; rysuje  │      │  co ~6 h; jedyna ścieżka       │
   │  segment; max co 300 s      │      │  z powiadomieniami)            │
   │  odpala pace.sh w tle)      │      └────────────────────────────────┘
   └─────────────────────────────┘
            │ spawn --compute-only (detached)
            ▼
   pace.sh = SSOT progów i projekcji + historia CSV + decyzja o powiadomieniu
```

- **Źródła danych**: (a) w sesji — pole `rate_limits` ze stdin paska statusu
  (CC ≥ 2.1.x, zero sieci); (b) poza sesją — `GET api.anthropic.com/api/oauth/usage`
  z tokenem z `.credentials.json` (nagłówki `anthropic-beta: oauth-2025-04-20` +
  `User-Agent: claude-code/<wersja>`; wersję CC pasek zapisuje do cache).
- **Powiadomienia tylko z natywnego Termuxa** — z proot się nie da
  (`app_process` nie linkuje; mostek tmux odrzucony, bo zakłóca żywą sesję).
  W sesji ostrzeżenie i tak widać w pasku (⚠).
- **Historia**: każdy nowy odczyt dopisuje wiersz do `~/.claude/usage-history.csv`
  (timestamp, utilization_5h, utilization_7d, projection_pct, status) — do analizy,
  ile % tygodniówek realnie konsumujemy.

## Progi (strojenie)

Wszystkie w **jednym bloku konfiguracji na górze `pace.sh`** (komentarze po polsku):

| Parametr | Domyślnie | Znaczenie |
|---|---|---|
| `GRACE_HOURS` | 12 | po resecie zawsze OK (za mało danych) |
| `EARLY_LOW_PROJECTION_PCT` | 50 | środek okna: LOW gdy projekcja < 50% |
| `ENDGAME_HOURS` | 48 | ile godzin przed resetem tryb agresywny |
| `ENDGAME_REMAINING_PCT` | 15 | końcówka: LOW gdy zostało > 15% limitu |
| `NOTIFY_COOLDOWN_H` | 6 | min. odstęp między powiadomieniami |
| `CACHE_TTL_S` | 300 | świeżość cache (s) — poniżej zero fetchy |
| `STALE_HOURS` | 2 | po tylu h dane = przeterminowane (`→?`) |
| `GRACE_HOURS_5H` | 0.5 | start okna 5h bez projekcji (zbyt rozchwiana) |

Po zmianie progów nic nie trzeba restartować — następny przebieg czyta nowe wartości.
Pamiętaj zsynchronizować zmianę do repo (`addons/usage-pace/files/usage/pace.sh`).

## Instalacja

1. **proot**: `bash addons/usage-pace/install.sh` — backup paska + golden test,
   kopiuje skrypty, podmienia wrapper, weryfikuje regresję (przy błędzie sam
   przywraca backup). `settings.json` nie jest ruszany.
2. **Termux** (jedyny krok ręczny, bo rejestracja jobu nie działa z proot):
   ```
   bash ~/.claude/usage/install-termux.sh
   ```
   Rejestruje job co 6 h (Android nie umie „punktualnie 12:00" — tylko okresowo),
   wysyła testowe powiadomienie i robi pierwszy przebieg.

## Diagnostyka

```
bash ~/.claude/usage/pace.sh --status        # czytelny status po polsku
bash ~/.claude/usage/pace.sh --notify-test   # testowe powiadomienie (tylko Termux)
bash ~/.claude/usage/test/run-pace-tests.sh  # testy progów (11 scenariuszy)
tail ~/.claude/usage/pace.log                # log przebiegów
```

Typowe sytuacje:
- **`→?` w pasku / STALE** — endpoint nie odpowiada albo token wygasł; token
  odświeża się sam przy następnej sesji Claude. Zero powiadomień, zero błędów.
- **Brak segmentu** — CC nie przysłał `rate_limits` i cache starszy niż 2 h.
  Pasek wygląda dokładnie jak przed instalacją.
- **Endpoint zwraca 429/401 na stałe** — system degraduje się do trybu STALE;
  nic nie crashuje. Sprawdź `pace.log`.

## Odinstalowanie / rollback

```
bash ~/.claude/usage/rollback.sh            # przywraca pasek z backupu + instrukcja odwołania jobu
bash ~/.claude/usage/rollback.sh --purge    # j.w. + kasuje cache/historię/skrypty (pyta o zgodę)
```

Ponowne włączenie po rollbacku:
```
cp ~/.claude/usage/statusline-wrapper.usage-pace.mjs ~/.claude/statusline-wrapper.mjs
```

## Pliki

| Plik (runtime) | Rola |
|---|---|
| `~/.claude/statusline-wrapper.mjs` | pasek + segment (patch istniejącego) |
| `~/.claude/usage/pace.sh` | SSOT: projekcja, progi, historia, powiadomienia |
| `~/.claude/usage/pace-job.sh` | cel termux-job-scheduler (Termux) |
| `~/.claude/usage/install-termux.sh` | rejestracja jobu + test (1 wklejka usera) |
| `~/.claude/usage/rollback.sh` | powrót do stanu sprzed instalacji |
| `~/.claude/usage-cache.json` | wspólny cache (wszystkie okna + scheduler) |
| `~/.claude/usage-history.csv` | historia odczytów do analizy |
| `~/.claude/statusline-wrapper.mjs.bak-*` | backup oryginalnego paska |
