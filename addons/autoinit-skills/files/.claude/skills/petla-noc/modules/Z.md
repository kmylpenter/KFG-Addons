# Moduł Z — KATALOG PÓL ZEWNĘTRZNYCH (Zoho CRM → arkusz-baza)

Cel: przygotować i pilnować migracji „apka żyje w 100% bez Zoho". Co noc, READ-ONLY i
accretywnie: zinwentaryzować KAŻDE pole Zoho, którego apka realnie używa, sklasyfikować
użycie + potencjał, zmapować na docelowy store w arkuszu, a po jednorazowym włączeniu przez
usera — ADDYTYWNIE zapisać katalog do arkusza.

Granice (NIE-cele, świadome):
- Z **NIE migruje danych biznesowych** (rekordów deali). Realny sync Zoho→arkusz to runtime
  pipeline aplikacji (trigger/Deluge), nie praca nocnego sprzątacza. Katalog *przygotowuje
  i pilnuje* odcięcia, nie wykonuje go. Mówże to wprost w raporcie — sam katalog nie odcina Zoho.
- Z **NIC nie kasuje/nadpisuje DANYCH BIZNESOWYCH** — inwariant 3 obowiązuje MIMO wyboru usera „noc
  pisze do arkusza" (user uchylił „bez zapisu zewnętrznego", NIE „nic nie usuwać"). Zapis store =
  ADDYTYWNY; zakładka-meta `__KATALOG_POL` = ODWRACALNY-rewrite (noc-owned + snapshot) — dwie różne
  gwarancje, obie spójne z INV3 (Z6/Z7).

Wzorce wykrywania pól: `shared/gas-rules.md` §11 (SSOT — nie powielać tutaj).
Model-per-rola: DISCOVERY (ekstrakcja) → subagent `model="sonnet"`; KLASYFIKACJA użycia,
POTENCJAŁ, MAPOWANIE, generacja writera → model sesji (osąd). Patrz SKILL.md „MODEL PER MODUŁ".

## Z0. Czy projekt dotyka Zoho? (bramka taniości — moduł jest zawsze-ON)

Tani test: `grep -lriE 'zoho|DEALS_DATA|/Deals|crm[_-]?webhook'` po `.gs/.html/.java`.
Zero trafień → `modules.Z.state=skipped` (note „brak Zoho") + jedno zdanie do raportu; koniec
w sekundy. (Zawsze-ON w F→K oznacza pusty, tani przebieg na projektach bez Zoho — nie błąd.)

## Z1. DISCOVERY (read-only, sonnet) — co apka FAKTYCZNIE czyta z Zoho

**Zasada źródła: ZERO pobrania z Zoho.** Pola, które apka wyświetla/używa (kalendarz, zakładki,
cały frontend Terminatora), są STATYCZNIE w kodzie — jako nazwy API w mapperach (Zoho→local),
stałych i porównaniach. Katalogujemy WYŁĄCZNIE to, co kod referuje; NIE enumerujemy schematu Zoho
(tam jest bałagan setek nieużywanych pól — celowo go nie dotykamy). Wszystkie nazwy API Zoho
przechodzą przez granicę mappera (`mapZohoDealToDashboard` / `handleCrmWebhook`), więc skan
mapperów łapie KAŻDE pole docierające do frontendu (klient .html używa już nazw lokalnych).

Fan-out per projekt. Zbierz UNIĘ pól ze WSZYSTKICH loci z `gas-rules.md` §11 (tabela Kind:
record-dot, field-list, webhook-cols, store-headers, write-back, dictionary-opcjonalny) — §11 jest
SSOT (INV8), NIE powielaj tu tej listy. Re-grep co noc (NIE hardkoduj numerów linii — dryfują).
Z-specyficzne wskazówki (poza §11): mapper znajdziesz jako funkcję z `.map(` na odpowiedzi `/Deals`
lub na payloadzie webhooka; **`access_kind` zapisz per pole** (zwł. `write-back` — kluczowe dla
dual-write w R, patrz Z4 i moduł R).

Wynik per pole: `{zoho_api_name, zoho_label?, type?, access_kind, loci:[file:line]}`.
Label ≠ API (konwencja Zoho, gas-rules §11) — ZAWSZE bierz API z KODU (słownik najwyżej potwierdza
typ/label), nie z labela.

## Z2. KLASYFIKACJA UŻYCIA (osąd, model sesji) — „czy na pewno używane"

KAŻDE pole w katalogu jest z definicji referowane w kodzie (Z1 — to jest cała pointa: lista pól
= to, czego apka używa, nie schemat Zoho). Klasyfikacja per pole, z `map.json` (moduł A) +
dead-candidates (moduł E):
- `active` — osiągalne z entry-pointu (handler/trigger/`google.script.run`) realną ścieżką;
- `candidate` — referencja TYLKO w martwym/nieosiągalnym kodzie (do przeglądu — może odpaść z apką).
Pól, których KOD NIE referuje, w katalogu NIE MA. (Opcjonalnie, gdy chcesz widok „co świadomie
pomijamy": appendix z różnicy słownik∖kod — `status: unused`, czysto informacyjny, NIE trafia do arkusza.)

## Z3. POTENCJAŁ (osąd, model sesji) — „czy ma potencjał być użyte w przyszłości"

Domyślny zakres = pola JUŻ referowane w kodzie (Z1). `future_potential: high|med|low` + 1 linia.
`high`: pole niesie znaczenie biznesowe (kwota, data, atrybut klienta/umowy), wskazane w planach
(`thoughts/shared/plans/*`), albo używane w SIOSTRZANEJ apce (Terminator↔TTA). `low`: incydentalne,
duplikaty labeli. Brak sygnału → `med`. (Opcjonalny „kandydat do adopcji" — pole ze STATYCZNEGO
słownika spoza kodu, które warto by zacząć używać — TYLKO na życzenie; oznacz osobno jako propozycję,
nie wpis migracyjny.)

## Z4. MAPOWANIE NA STORE (osąd, model sesji)

Cel = store z kodu (wybór usera): Terminator `Główna baza danych` (`MAIN_DB_COLUMNS`),
TTA `DEALS_DATA` (`COLS`). Per pole: `db_tab`, `db_column` (proponowana = `zoho_api_name`, chyba
że store ma już własną nazwę kolumny dla tego znaczenia), `migration_status`:
`not_started | column_proposed | column_exists | mirrored | cutover`
(`cutover` = apka czyta to pole ze store, nie z Zoho — koniec migracji pola).
`active`/`high` bez kolumny w store → propozycja kolumny → DECYZJE raportu.

## Z5. KATALOG (artefakt SSOT, wersjonowany net)

Zapisz `<projekt>/.petla-noc/zoho-catalog.yaml` (net jak `tests/` — niecommitowany przez noc,
user commituje rano). Per pole pełny wpis Z1–Z4 + `last_verified: <data>`. MERGE IDEMPOTENTNY:
- nowe pole → dodaj; istniejące → zaktualizuj (status/potencjał/mapowanie/last_verified);
- pole znikłe z kodu → **NIE kasuj**: `status: unused` + `last_seen: <data>` (inwariant 3).
Słownika `docs/zoho_*_api_names.md` (ręczny, dzielony między 2 terminale wg jego protokołu) **NIE
dotykaj** — tylko RAPORTUJ rozjazd (pole w kodzie spoza słownika; w słowniku z błędnym typem;
Gotcha-niespójność label↔API). Schemat wpisu (= „struktura dla AI"):
```yaml
- zoho_api_name: Przewidywany_Montaz
  zoho_label: "Przewidywany montaż"
  type: Date
  status: active            # active | candidate | unused
  future_potential: high    # high | med | low  (+ rationale)
  rationale: "data montażu — rdzeń kalendarza"
  used_by: [{app: Terminator-Umowy, where: "kalendarz/buildCalendar", access_kind: record-dot}]
  access_kind: record-dot   # FIELD-LEVEL rollup (decyzja dual-write w R): = write-back jeśli KTÓRYKOLWIEK
                            # locus w used_by[] to write-back; inaczej read. Brak → R traktuje jak read (mirror-only, fail-safe C2).
  db_tab: "Główna baza danych"
  db_column: Przewidywany_Montaz
  migration_status: column_proposed
  last_verified: 2026-06-18
```

## Z6. GENEROWANA FUNKCJA ZAPISU (mutacja → BRAMKA; jak `_errors.gs`)

Wygeneruj/uaktualnij `<projekt>/_zoho_catalog.gs` — GENERYCZNY writer (dane lecą w payloadzie,
nie wkompilowane w kod). Podlega BRAMCE jako plik TWORZONY (SKILL.md: zielony PEŁNY harness PO);
generacja **za bramką, NIGDY w RED** (jak E/R).
Kontrakt bezpieczeństwa (store = addytywny; `__KATALOG_POL` = odwracalny-rewrite — NIE myl):
- **OWNERSHIP-GUARD (C1)**: `__KATALOG_POL` zapisuj pełnym rewrite TYLKO gdy zakładka nosi stempel
  noc-created (Developer-Metadata `petla-noc-owned`, ustawiany przy PIERWSZYM utworzeniu zakładki).
  Zakładka o tej nazwie BEZ stempla = kolizja z czymś ludzkim → `would_modify` + DECYZJE, **nigdy**
  rewrite. „Noc ją w 100% POSIADA" jest GWARANTOWANE stemplem, nie założeniem o nazwie.
- ADDYTYWNIE dokleja brakujące kolumny do store (wzór: istniejący `getOrCreateMainDbSheet_`);
- **additive-guard**: USUNIĘCIE / RENAME / PRZESTAWIENIE kolumny store albo nadpisanie komórki danych
  → NIE wykonuj, `would_modify:[…]` → DECYZJE. **Rename-vs-add rozstrzygaj po stabilnym kluczu**
  (`zoho_api_name`): nagłówek store nieobecny w `rows` ORAZ wiersz katalogu, którego `db_column`
  zniknął z nagłówków → możliwy rename → `would_modify` (FAIL-CLOSED), nie doklejaj na ślepo;
- **snapshot PRZED zapisem** → zakładka `__KATALOG_SNAPSHOT` (+ ref do progress). Rollback DWUczęściowy:
  (a) meta-tab → przywróć z `__KATALOG_SNAPSHOT`; (b) doklejone kolumny store są ADDYTYWNE — snapshot
  ich NIE cofa; raport wylicza „bezpieczne zostawić lub ręcznie usunąć kolumnę X".

Skeleton (emitowany artefakt — INV6):
```js
// _zoho_catalog.gs — GENEROWANY przez petla-noc moduł Z. Addytywny, odwracalny. NIE edytuj ręcznie.
function __nocZohoCatalogSync_(payload) {              // payload = {rows:[…], dryRun:bool}
  var ss   = __nocStoreWorkbook_();                    // ten sam workbook co store (openById z kodu apki)
  var diff = __nocCatalogDiff_(ss, payload.rows);      // {additive_cols, would_modify}; rename→would_modify (fail-closed)
  if (!__nocOwnsMetaTab_(ss))                          // C1 ownership-guard
    diff.would_modify.push('__KATALOG_POL bez stempla noc-created — kolizja');
  if (payload.dryRun) return diff;                     // preview do raportu (Z7 dryRun=true najpierw)
  if (diff.would_modify.length) return diff;           // STOP — nic destrukcyjnego (additive-guard + ownership)
  var snap = __nocSnapshot_(ss);                       // przed zapisem (rollback ref)
  __nocWriteMetaTab_(ss, payload.rows);                // odwracalny rewrite __KATALOG_POL (noc-owned, ostemplowany)
  __nocAppendStoreCols_(ss, diff.additive_cols);       // tylko DOKLEJ brakujące kolumny
  return Object.assign(diff, {snapshot: snap, written: true});
}
```

## Z7. ZAPIS — kiedy/jak (wykonywany w DEPLOY NOCNY krok D6, nie w pętli modułów)

Sam zapis NIE idzie z pętli F→K — idzie w DEPLOY NOCNY (link nocny istnieje, kod nocny
wystawiony). Patrz SKILL.md „DEPLOY NOCNY" D6. Sekwencja:
1. POST katalogu na `night_deployment_url` (action `__noc_zoho_catalog_sync`) z `dryRun:true`
   → odbierz `diff`. `would_modify` NIEpuste → zapis POMINIĘTY, `would_modify` → DECYZJE.
2. `would_modify` puste → POST z `dryRun:false` → zapis (meta-tab + doklejone kolumny) + snapshot.
3. **JEDNORAZOWE WŁĄCZENIE**: routing `__noc_zoho_catalog_sync` to CORE kod — noc go **NIE edytuje
   bezobsługowo**. 1. noc: generuje funkcję + DECYZJA z miejscem wpięcia **PER APKA** (dispatchery
   się różnią — ground-truth): **Terminator** → nowy `if (action === '__noc_zoho_catalog_sync') {…}`
   w `doPost` (top-level to łańcuch `if(action===)`, NIE `switch/case`); **TTA** → `case` w routerze
   `doGet` (`doPost` forwarduje `action` do `doGet`, więc w `doPost` go nie ma). Do czasu wpięcia:
   zapis POMINIĘTY (katalog i tak świeży w repo) + raport. Po wpięciu (raz, ręcznie) — automatyczny co noc.
Warunki skip (jak D2/D3): brak `.clasp.json`/clasp/auth, RED, projekt degraded, brak commitu
kodu nocnego → POMINIĘTY + powód w raporcie (NIE pytaj).

## Wyjścia Z

- `<projekt>/.petla-noc/zoho-catalog.yaml` (net); `_zoho_catalog.gs` (generowany, za bramką);
- progress: blok `zoho` (ścieżka katalogu, liczniki active/candidate/unused, `last_write`,
  `snapshot_ref`, `endpoint_wired`) + `modules.Z`;
- sekcja raportu „MIGRACJA ZOHO→ARKUSZ" (nowe/zmienione pola, score migracji) + DECYZJE
  (kolumny do dodania, rozjazd ze słownikiem, jednorazowe wpięcie endpointu);
- snapshot ref do rollbacku (`__KATALOG_SNAPSHOT`).
