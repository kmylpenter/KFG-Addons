# Corpus Maintenance — utrzymanie pamięci i reguł

Meta-reguła: jak utrzymywać ten korpus (rules + memory + learnings DB), żeby przeżył zmiany modeli. Spisana 2026-06-12.

## Inwarianty (twarde)
1. **Backup przed kasowaniem/nadpisaniem.** Nigdy `rm` na pamięci/regule. Archiwizacja = tar do `~/.claude/backups/<data>-<powod>/` ALBO `mv` do `~/.claude/rules-archive/` z wierszem w tamtejszym README (plik, data, powód, warunek przywrócenia).
2. **Mechanizm > procedura > notatka.** Zanim dopiszesz regułę, sprawdź czy da się to wymusić hookiem/bramką — reguła wymaga pamięci modelu, mechanizm nie.
3. **Reguła musi płacić czynsz.** Każdy plik w `rules/` jest ładowany do KAŻDEJ sesji. Dopisując ~50 linii, wskaż co najmniej tyle samo do wycięcia/scalenia. Wpis, który nie zmienia zachowania modelu, to czysty koszt.

## Kiedy co zapisać
| Co | Gdzie |
|----|-------|
| Trwały fakt o userze/projekcie, który KAŻDA sesja musi znać bez pytania | `projects/<proj>/memory/*.md` + linia w MEMORY.md |
| Sytuacyjna lekcja/fix/decyzja (long tail, do odnalezienia na żądanie) | learnings DB (`store_learning.py`, patrz dynamic-recall) |
| Korekta zachowania modelu potwierdzona ≥2 incydentami | `rules/*.md` (z sekcją LESSON LEARNED i "dlaczego") |
| Jednorazowy kontekst sesji | nigdzie — ginie z sesją, i dobrze |

## Higiena wpisów pamięci
- Każdy wpis: data weryfikacji + co go unieważnia (jeśli da się nazwać). Bez tego wpis po migracji środowiska wprowadza w błąd z pełnym przekonaniem.
- Aktualizuj istniejący plik zamiast tworzyć duplikat; wpis błędny → popraw albo zarchiwizuj (inwariant 1), nie zostawiaj obok poprawnego.
- Indeks MEMORY.md: 1 linia na wpis, bez treści; linki tylko do plików w `memory/` (link poza katalog = zgniły link po przeniesieniu projektu).

## Przegląd okresowy (MOT)
Przy naturalnej przerwie raz na ~2 tygodnie albo po dużej zmianie środowiska (migracja, upgrade pythona/node):
1. `bash ~/.claude/scripts/infra-selftest.sh` — deterministyczny test żywotności (recall, memory.db, tldr, hooki, dysk); FAIL → napraw zanim zaufasz regułom, które to narzędzie reklamują.
2. `/mot` (skill) — głębsze zdrowie skills/agents/hooks/memory.
3. Wpisy pamięci dotknięte zmianą środowiska → zaktualizuj status zamiast kasować.

## Granica szczerości
Raport z utrzymania zawsze nazywa: co naprawione, czego NIE ruszono i dlaczego, co czeka na decyzję usera. Sprzątanie, które ukrywa swoje pominięcia, jest gorsze niż brak sprzątania.
