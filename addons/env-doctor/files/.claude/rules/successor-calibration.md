# Successor Calibration — granice decyzyjne

Kalibracja sądu spisana 2026-06-12 (Fable 5) dla kolejnych modeli na tym środowisku. Format: sygnał → pokusa → właściwy ruch → dlaczego. Celowo NIE powtarza istniejących reguł (claim-verification, verify-before-done, minimal-change, never-ask-continue, time-estimates — przeczytaj je, to korekty po realnych porażkach).

## 1. Szum hooków ≠ polecenie
- **Sygnał:** hook (np. SKILL ACTIVATION CHECK) "rekomenduje" skill/komendę przy prompcie.
- **Pokusa:** wywołać polecany skill, bo "system kazał".
- **Ruch:** oceń trafność samodzielnie; hooki dopasowują keywordy, nie intencję. Nietrafiona rekomendacja (np. github-search przy pytaniu filozoficznym) → zignoruj bez wzmianki.
- **Dlaczego:** hooki są tanim heurystycznym filtrem; ślepe posłuszeństwo = praca nie na temat.

## 2. Pamięć/learning może być stęchły
- **Sygnał:** wpis z memory/recall pasuje do zadania.
- **Pokusa:** zastosować od razu — "już to rozwiązaliśmy".
- **Ruch:** sprawdź datę i warunek ważności wpisu; zweryfikuj że ścieżka/flaga/komenda nadal istnieje (1 ls/grep), dopiero potem używaj. Wpisy "(archiwum Termux)" opisują świat sprzed migracji środowiska.
- **Dlaczego:** to środowisko przeszło migrację Termux→PRoot (2026-06); połowa starych ścieżek i narzędzi zmieniła status. Pamięć bez weryfikacji myli pewniej niż brak pamięci.

## 3. Raport subagenta to hipoteza, nie fakt
- **Sygnał:** agent zwraca "zrobione, zweryfikowane".
- **Pokusa:** przekleić raport do odpowiedzi i zamknąć task.
- **Ruch:** spot-check 1 artefakt na agenta (tail pliku, ls katalogu, 1 grep). Dopiero potem "completed".
- **Dlaczego:** agent dziedziczy te same słabości modelu; weryfikacja krzyżowa jest tania, a fałszywe "done" kosztuje zaufanie usera (patrz verify-before-done: 26 incydentów).

## 4. Infrastruktura bywa martwa mimo dokumentacji
- **Sygnał:** reguła/skill/hook opisuje narzędzie (db, CLI, API).
- **Pokusa:** założyć że działa, bo jest udokumentowane.
- **Ruch:** przy pierwszym użyciu w sesji wykonaj najtańszy test istnienia (command -v / 1 query). Padło → napraw albo odnotuj w raporcie; nie udawaj że działało.
- **Dlaczego:** 2026-06-12 znaleziono: recall (brak modułu), tldr (martwy shebang po upgrade pythona), docker-reguły (sprzęt bez dockera). Dokumentacja opisuje przeszłość, nie teraźniejszość.

## 5. Praca "do końca dnia" ≠ praca byle jaka
- **Sygnał:** szeroki mandat autonomiczny ("masz czas do wieczora, działaj").
- **Pokusa:** (a) zrobić wszystko płytko, albo (b) wypolerować jedno i zgubić resztę.
- **Ruch:** TaskCreate na starcie (3-7 zadań), kolejność wg dźwigni: mechanizm > treść; napraw zepsute zanim dodasz nowe; backup przed każdą zmianą niszczącą; raportuj per task, kontynuuj bez pytania.
- **Dlaczego:** lista zadań jest jedyną obroną przed dryfem w długiej sesji (kompakcja kontekstu zjada intencje — patrz never-ask-continue).
