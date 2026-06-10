# gas-rules.md — JEDYNA kopia reguł Google Apps Script (SSOT)

> Czytana przez WSZYSTKIE moduły petla-noc. ŻADEN moduł ani SKILL.md nie kopiuje
> tych list — tylko wskazuje tutaj. Zmiana reguły = edycja TEGO pliku.

## 1. HANDLERY SPECJALNE (nigdy nie kwarantannować, zawsze entry point)

Simple + installable triggers oraz web-app:
```
onOpen  onEdit  onInstall  onSelectionChange  onFormSubmit  onChange
doGet  doPost
```
Dodatkowo entry pointami są: każda funkcja wskazana w 2. (wywołania dynamiczne)
oraz funkcje wywoływane przez biblioteki zewnętrzne (patrz 6.).

## 2. WYWOŁANIA DYNAMICZNE (martwy kod NIEWYKRYWALNY statycznie bez tych wzorców)

Wzorce do skanowania (`.gs` ORAZ `.html` — w HTML też inline `<script>`):

| Kind | Wzorzec (regex, na nazwę funkcji w grupie 1) |
|---|---|
| trigger | `ScriptApp\s*\.\s*newTrigger\s*\(\s*['"]([A-Za-z_$][\w$]*)['"]` |
| menu | `\.addItem\s*\(\s*[^,]+,\s*['"]([A-Za-z_$][\w$]*)['"]` |
| menu-sub | `\.addSubMenu\(...\).addItem(...)` — ten sam wzorzec addItem |
| gsrun | `google\s*\.\s*script\s*\.\s*run(?:\s*\.\s*with\w+Handler\s*\([^)]*\))*\s*\.\s*([A-Za-z_$][\w$]*)\s*\(` |
| gsrun-handler | `with(Success|Failure)Handler\s*\(\s*([A-Za-z_$][\w$]*)\s*[,)]` (handler po stronie HTML) |
| html-template | `<\?!?=?\s*([A-Za-z_$][\w$]*)\s*\(` (scriptlety `<?= f() ?>` w templated HTML) |
| include | `createTemplateFromFile|HtmlService\.createHtmlOutputFromFile` → nazwa PLIKU html (zależność plikowa) |
| callback-string | KAŻDY string literal będący dokładnie (word-boundary) nazwą zdefiniowanej funkcji |

Reguła `callback-string` jest NAJSZERSZA i rozstrzygająca dla kwarantanny:
nazwa funkcji występująca w JAKIMKOLWIEK stringu w `.gs`/`.html` (porównanie
case-sensitive, całe słowo) → funkcja NIE kwalifikuje się jako martwa.

## 3. KWALIFIKACJA DO KWARANTANNY (moduł E — warunki ŁĄCZNE)

1. Zero referencji statycznych w `.gs` (poza własną definicją).
2. Zero referencji w `.html` (w tym wzorce z sekcji 2).
3. Nazwa nieobecna w żadnym stringu (`callback-string` powyżej).
4. Nie jest handlerem specjalnym (sekcja 1) ani celem triggera/menu/gsrun.
5. OPCJONALNIE (jeśli istnieje `runtime-log.json`): zero wykonań w ostatnich 30 dniach.
6. DOUBT-RULES (każda → skip + raport, NIE kwarantanna):
   - nazwa krótka (<4 znaki) lub generyczna (update, init, run, main, test, get, set…),
   - projekt jest/może być biblioteką (sekcja 6),
   - funkcja przypisywana do zmiennej/obiektu (`var f = nazwa`, `obj.x = nazwa`),
   - jakakolwiek niepewność parsowania (eval, new Function, this[...], obj[name]()).

## 4. BATCH OPERATIONS (moduł D lens gas-batch, klasy z audytu petli)

Antywzorce (major, w pętli = critical przy dużych zakresach):
- `getValue()` / `setValue()` / `getRange(r,c)` wywoływane W PĘTLI
  → zamień na jedno `getValues()` / `setValues()` na całym zakresie.
- `appendRow()` w pętli → zbierz tablicę + jeden `setValues()`.
- `SpreadsheetApp.flush()` w pętli.
- Naprzemienne read/write na tym samym arkuszu w pętli (każda zmiana kierunku = roundtrip).
- `getDataRange()` wołane wielokrotnie zamiast raz do zmiennej.

## 5. LIMITY GAS (kontekst dla auditów; źródło: quotas Apps Script)

- Wykonanie: max 6 min (consumer) / 30 min (Workspace) — funkcje >200 linii
  i pętle bez batch są głównym ryzykiem timeoutu.
- Quoty dzienne (rzędy wielkości): MailApp ~100/dzień consumer; UrlFetch ~20k/dzień;
  triggers ~90 min/dzień łącznego czasu. PropertiesService: ~500 KB łącznie,
  ~9 KB na pojedynczą wartość (istotne dla modułu P). Nie hardkoduj liczb
  w raportach jako pewnik — oznaczaj "orientacyjnie, sprawdź aktualne quotas".

## 6. RYZYKO BIBLIOTEKI

Projekt może być używany JAKO biblioteka przez inne projekty (wywołania
`Lib.funkcja()` są POZA naszym skanem). Sygnały: `appsscript.json` zawiera
`"library"` w deploymentach, README/nazwa sugeruje "lib/common/shared", user
oznaczył w config (`library: true` w progress.json).
→ Przy JAKIMKOLWIEK sygnale: kwarantanna w projekcie WYŁĄCZONA (report-only).

## 7. WZORZEC HEADER-MAP (moduł G — cel refaktoru)

```js
// Zamiast: var status = row[7];  sheet.getRange("C2:C").getValues();
const COL = (function () {
  const h = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  const m = {};
  h.forEach((name, i) => { m[String(name).trim()] = i; });
  return m;
})();
// Użycie: row[COL["Status"]]  — odporne na przestawienie kolumn.
```
Refaktor możliwy TYLKO gdy nagłówki da się ustalić ze ŹRÓDEŁ (stała HEADERS,
fixtures testów, komentarz z nagłówkami). Nie zgaduj nazw kolumn z arkusza,
którego nie widzisz → raport kandydata bez refaktoru.

## 8. WZORZEC WRAPPERA BŁĘDÓW (moduł I — cel wdrożenia)

```js
function withErrorLog(fnName, fn) {
  try {
    return fn();
  } catch (e) {
    try {
      var ss = SpreadsheetApp.getActiveSpreadsheet() || SpreadsheetApp.openById(CONFIG.ERRORS_SSID);
      var sh = ss.getSheetByName("Errors") || ss.insertSheet("Errors");
      sh.appendRow([new Date(), ScriptApp.getScriptId(), fnName,
                    String(e && e.message || e), String(e && e.stack || "")]);
    } catch (ignore) {}
    throw e;  // NIE połykamy — logujemy i rzucamy dalej
  }
}
// Wdrożenie per plik: ciała funkcji wywołujących UrlFetchApp/MailApp/GmailApp/
// SpreadsheetApp/CalendarApp opakowane: return withErrorLog("nazwa", function(){ ...orig... });
// ZAKAZ: funkcji używającej `this` lub `arguments` w ciele NIE opakowuj —
// przeniesienie ciała do wewnętrznej funkcji zmienia OBA (ES5), więc to nie
// byłoby zero-behavioral → report-only.
```
Wykrywanie połykania (lens gas-errors): `catch` z pustym ciałem; `catch` którego
ciało to wyłącznie `Logger.log`/`console.log`; wywołania w/w API poza jakimkolwiek `try`.

## 9. SEKRETY I KONFIGURACJA (moduł H)

- Hardkody do wykrycia: ID arkuszy/dokumentów (`[a-zA-Z0-9_-]{25,60}` w stringu —
  weryfikuj kontekstem openById/openByUrl/DriveApp), adresy e-mail, URL-e webhooków
  (hooks.slack.com, discord, chat.googleapis.com…), klucze API (reuse SECRET_PATTERNS
  z helpera ssot `detect_duplicates.py` — uruchom helper i konsumuj `secret_kind`).
- Cel migracji: `PropertiesService.getScriptProperties()` lub jeden obiekt `CONFIG`
  na początku projektu. (Moduł H = raport + propozycja; sama migracja to decyzja usera.)
- Martwa konfiguracja: klucz w `setProperty/getProperty` — zbierz oba zbiory;
  `set` bez żadnego `get` = martwy zapis; `get` bez `set` w kodzie = klucz
  konfigurowany ręcznie (do raportu jako "wymagany klucz środowiska", NIE błąd).

## 10. PARSOWANIE ŹRÓDEŁ (moduły A/B/C — wspólne zasady)

- Pliki do 20k linii: czytaj fragmentami (Read offset/limit), nigdy w całości.
- Definicje funkcji: `function NAME(...)`, `var/let/const NAME = function`,
  `NAME: function(...)` (obiekty), arrow `const NAME = (...) =>`.
- Wywołania statyczne: identyfikator + `(`, po wykluczeniu słów kluczowych
  (if/for/while/switch/catch/return/typeof/new) i metod (`obj.m()` liczy się
  dla `m` tylko jako "method-call", nie globalna funkcja).
- Top-level code w .gs wykonuje się przy KAŻDYM wywołaniu projektu — odnotowuj
  w map.json (`top_level: true` dla pliku) i w testach (ładowanie pliku = efekt).
