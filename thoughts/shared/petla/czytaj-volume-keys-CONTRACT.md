# Kontrakt: Voice Typer → czytaj "key-trigger" (klawisze głośności przez Accessibility)

**Dla Klauda utrzymującego klawiaturę Voice Typer** (pakiet `com.utilityhub.voicekeyboard`).
To jest prompt + specyfikacja. Wklej go tamtemu Klaudowi.

Ten kontrakt jest analogiczny do dwóch istniejących (`voice-typer-active-window-CONTRACT.md`
i `voice-typer-recording-flag-CONTRACT.md`): **klawiatura/Accessibility pisze flagę, czytaj ją
czyta.** Tu flaga niesie naciśnięcie klawisza głośności.

## Po co to

`czytaj` ma pod klawiszem głośności dwie akcje (działają, gdy user patrzy na Termux):

- **Volume Up** → przeczytaj ostatnią wiadomość aktywnego okna (kolejne naciśnięcia w ciągu
  45 s cofają o wiadomość wstecz — "scrub back").
- **Volume Down** → pauza / wznowienie TTS (toggle).

Dziś czytaj łapie te klawisze, czytając surowe zdarzenia kernela `/dev/input/event*` przez
Shizuku/adb (`volume_watcher.py`). Problem: **dostarczenie naciśnięcia do czytnika w tle ma
podłogę ~3 s** (Shizuku-rish ~3–11 s, adb exec-out ~3 s) — to JEDYNE, co zostało z dawnych 11 s
opóźnienia (syntezę już rozwiązał cache audio: trafienie = natychmiast). Usługa Accessibility
dostaje `onKeyEvent` **natychmiast**, więc przechwycenie klawisza w voice typerze i zapisanie
flagi zbije tę podłogę do zera.

Voice typer ma już usługę `HybridAccessibilityService` (włączaną w Ustawienia → Dostępność dla
trybu hybrydowego) i już wie, kiedy Termux jest na wierzchu. Wystarczy ją **rozszerzyć** — nie
trzeba nowej usługi ani nowej apki.

## Co klawiatura ma zrobić

### 1. Config XML — włącz filtrowanie klawiszy

Plik: `apps/voice-keyboard/src/main/res/xml/hybrid_accessibility_config.xml`.

Dodaj `flagRequestFilterKeyEvents` do `accessibilityFlags` **oraz** atrybut
`android:canRequestFilterKeyEvents="true"`:

```xml
<accessibility-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:accessibilityEventTypes="typeWindowStateChanged|typeWindowsChanged"
    android:accessibilityFeedbackType="feedbackGeneric"
    android:accessibilityFlags="flagRetrieveInteractiveWindows|flagRequestEnhancedWebAccessibility|flagRequestFilterKeyEvents"
    android:canRetrieveWindowContent="true"
    android:canRequestFilterKeyEvents="true"
    android:canPerformGestures="false"
    android:description="@string/hybrid_a11y_description"
    android:summary="@string/hybrid_a11y_summary"
    android:notificationTimeout="100"/>
```

> ⚠️ Po tej zmianie system pokaże przy włączaniu usługi **dodatkowe ostrzeżenie** ("może
> obserwować wpisywany tekst / klawisze"), a usługę trzeba **wyłączyć i włączyć ponownie**, żeby
> nowy config się załadował. Uprzedź usera w UI/onboardingu.

### 2. `HybridAccessibilityService` — przejmij `onKeyEvent`

Plik: `apps/voice-keyboard/src/main/java/com/utilityhub/voicekeyboard/hybrid/HybridAccessibilityService.kt`.

Nadpisz `onKeyEvent`. Logika:

```kotlin
override fun onKeyEvent(event: KeyEvent): Boolean {
    val code = event.keyCode
    if (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN) {
        return false                                  // nie nasz klawisz — przepuść
    }
    // jedno odpalenie na fizyczne naciśnięcie: tylko DOWN, bez autorepeat
    if (event.action != KeyEvent.ACTION_DOWN || event.repeatCount != 0) return false

    // BRAMKA: działamy TYLKO gdy user patrzy na Termux. Reużyj istniejącej wiedzy o
    // oknie na wierzchu (currentForegroundPackage). Termux ma FLAG_SECURE → jego
    // pakiet czyta się jako null, więc "null lub com.termux" = dozwolone.
    val fg = currentForegroundPackage
    val inTermux = (fg == null || fg == "com.termux")
    if (!inTermux) return false                       // poza Termuksem — normalna głośność

    val key = if (code == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down"
    writeKeyTrigger(key)                              // patrz niżej
    return false                                      // PRZEPUŚĆ — głośność dalej działa
}
```

**Ważne — `return false` (przepuszczamy klawisz), NIE konsumujemy.** User chce, żeby głośność
nadal działała normalnie. Gdy Termux jest na wierzchu i tak sam łyka klawisz głośności (terminal
go rezerwuje), więc system nie podbije głośności — zachowanie identyczne jak dziś z evdev.

### 3. Zapis flagi (atomowo, z timestampem)

- **Plik flagi:** `/storage/emulated/0/Download/Termux-flags/czytaj-keytrigger.flag`
  (ten sam katalog co `czytaj-active-window.flag` i `voice-typer-recording.flag` — zapisywalny
  dla apki, czytelny dla czytaj z PRoot).
- **Format:** dokładnie JEDNA linia = `<key> <ms>`, gdzie:
  - `<key>` = `up` (Volume Up) albo `down` (Volume Down),
  - `<ms>` = `System.currentTimeMillis()` — epoch w milisekundach, **UNIKALNY na każde
    naciśnięcie**. To po nim czytaj odróżnia NOWE naciśnięcie od starej flagi. Bez `<ms>` poller
    nie rozpozna dwóch identycznych naciśnięć pod rząd → **timestamp jest wymagany**.
  - Przykład: `up 1733230000123`
- **Atomowo:** zapis do pliku tymczasowego + `rename` (dokładnie tak jak `ActiveWindowNotifier`
  pisze active-window) — czytaj nigdy nie złapie połowy linii.

```kotlin
private fun writeKeyTrigger(key: String) {
    try {
        val dir = java.io.File("/storage/emulated/0/Download/Termux-flags")
        dir.mkdirs()
        val tmp = java.io.File(dir, "czytaj-keytrigger.flag.tmp")
        val dst = java.io.File(dir, "czytaj-keytrigger.flag")
        tmp.writeText("$key ${System.currentTimeMillis()}")
        tmp.renameTo(dst)
    } catch (e: Throwable) {
        FileLogger.log("HybridA11y", "keytrigger write failed: ${e.message}")
    }
}
```

(Opcjonalny debounce ~300 ms na ten sam klawisz jest mile widziany, ale nieobowiązkowy — strona
czytaj i tak debounce'uje 0.4 s.)

## Strona czytaj (JUŻ ZROBIONE — nie ruszasz)

`volume_watcher.py` dostał wątek-poller, który ~co 80 ms czyta `czytaj-keytrigger.flag`,
porównuje `<ms>` (nowy timestamp = nowe naciśnięcie) i **natychmiast** odpala akcję
(`up` → read-back, `down` → pauza). Poller **ufa bramce Termux-foreground z apki** i NIE
sprawdza foregroundu ponownie (ten check kosztuje ~1.8 s — pominięcie go to właśnie sekret
natychmiastowości). Stary czytnik evdev (Shizuku/adb) zostaje jako **fallback przy zgaszonym
ekranie** i "schodzi z drogi", gdy płyną flagi (prymat flagi przez ~12 s), żeby jego wolne echo
tego samego naciśnięcia nie odpaliło akcji drugi raz.

Gdy flagi nie ma (usługa niewłączona / stary build) — czytaj działa po staremu przez evdev (zero
regresji).

## Ekran zgaszony — DO ZWERYFIKOWANIA

`onKeyEvent` w usłudze Accessibility **prawdopodobnie NIE odpala się przy zgaszonym ekranie**
(urządzenie nieinteraktywne — klawisze głośności idą wprost do strumienia audio, z pominięciem
Accessibility). To trzeba **potwierdzić na urządzeniu**. Jeśli faktycznie nie odpala:
- nic nie tracimy — evdev (Shizuku/adb) i tak obsługuje przypadek zgaszonego ekranu jak dziś;
- po prostu natychmiastowa ścieżka działa tylko przy włączonym ekranie.

Jeśli `onKeyEvent` JEDNAK odpala się przy zgaszonym ekranie — bonus, mamy natychmiast również w
trybie hands-free. Zaloguj wynik testu w `FileLogger`, żeby było wiadomo.

## Test akceptacyjny

1. Włącz/wyłącz-i-włącz usługę Accessibility voice typera (po zmianie config XML musi się
   przeładować). Sprawdź `FileLogger` — `HybridA11y connected`.
2. Termux na wierzchu, naciśnij **Volume Up** → plik `czytaj-keytrigger.flag` ma `up <ms>`, a
   czytaj czyta ostatnią wiadomość **prawie natychmiast** (cache-hit = zero syntezy).
3. Naciśnij **Volume Down** → flaga `down <ms>`, TTS pauzuje; znów Volume Down → wznawia.
4. Wyjdź z Termuksa (ekran domowy), naciśnij głośność → **flaga się NIE zmienia**, głośność
   zmienia się normalnie.
5. W `~/.claude/czytaj.log` widać `VOLKEY keytrigger up` / `down` i zaraz potem `read-back` /
   `pause`. Porównaj czas reakcji ze starą ścieżką evdev (powinno być ~natychmiast vs ~3 s).
6. Test ekranu zgaszonego (punkt wyżej) — zanotuj, czy flaga powstaje przy zgaszonym ekranie.

## Dlaczego tak (skrót decyzji)

- **Rozszerzamy istniejącą usługę, nie nową apkę** — `HybridAccessibilityService` już istnieje,
  już zna foreground Termuksa, już pisze flagę active-window tym samym wzorcem.
- **Flaga + szybki poller (nie RUN_COMMAND)** — RUN_COMMAND dokłada setki ms i rozruch basha;
  flaga + 80 ms poll jest lżejsza i niżej-opóźniona, a poller już działa w czytaj.
- **Przepuszczamy klawisz (return false)** — głośność ma działać normalnie; w Termuksie i tak
  klawisz jest pochłaniany przez terminal.
- **Prymat flagi nad evdev** — gdy płyną flagi (ekran on), evdev stoi, bo jego echo przychodzi
  3–11 s później i podwoiłoby akcję; evdev wraca do gry, gdy flag brak (ekran off / brak usługi).

## AKTUALIZACJA z testu na urządzeniu (2026-06-03)

Pierwszy test na Pixelu potwierdził **najważniejszą rzecz: usługa DZIAŁA** — po naciśnięciu
VolumeDown w Termuksie w katalogu pojawił się plik własności aplikacji (uid 10275) z treścią
dokładnie `down <13-cyfrowy ms>`. Czyli `onKeyEvent` odpala się, bramka Termux-foreground działa,
format jest poprawny. 🎉

**ALE** zapis utknął jako `czytaj-keytrigger.flag.tmp` — finalny `rename` na
`czytaj-keytrigger.flag` się nie dopełnił. To znany problem Androida: `File.renameTo()` na
pamięci współdzielonej (emulated / FUSE) bywa zawodny; dodatkowo rename nie nadpisze istniejącej
finalnej flagi, jeśli ta należy do innego uid.

**Co zrobiłem po stronie czytaj (już działa, nie musisz na to czekać):** poller czyta teraz
ZARÓWNO `…flag` JAK I `…flag.tmp` i bierze nowszy timestamp — więc system działa nawet gdy
rename zawiedzie. Zweryfikowane na żywo (poller łapie `.tmp` → read-back).

**Zalecenie dla Ciebie (czyściej, opcjonalne ale rekomendowane):** zamiast temp+rename **pisz
wprost do finalnego pliku**, jednym zapisem:

```kotlin
java.io.File(dir, "czytaj-keytrigger.flag").writeText("$key ${System.currentTimeMillis()}")
```

Pojedynczy ~18-bajtowy zapis jest dla pollera praktycznie atomowy (poller waliduje format i
dedupuje po ts, więc ewentualny rozdarty odczyt po prostu pominie i spróbuje za 80 ms). To
eliminuje zawodny `renameTo` i jest prostsze. (Nie używaj temp+rename z Javy tutaj — to właśnie
ono utknęło.) Active-window flaga może zostać na RUN_COMMAND+`mv` bo tam `mv` to shell Termuksa,
który działa; problem dotyczy tylko rename’u z procesu apki.

**Uwaga:** nic w PRoot/czytaj nie powinno pisać `czytaj-keytrigger.flag` (tylko czytać) — gdyby
PRoot zapisał ją jako root, zablokowałby rename apki. Poller jest read-only; pilnuj tego po
swojej stronie też.
