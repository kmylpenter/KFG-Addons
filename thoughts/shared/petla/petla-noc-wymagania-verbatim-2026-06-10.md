======================================================================
== QUEUED PROMPT @ line 3121, 2026-06-10T03:54:33.061Z ==
======================================================================
dopisz jako zadanie jeszcze to:
KONTEKST
Naprawiasz właśnie skill pętla-audyt (z wariantem pętla-solve: audyt znajduje błędy
w trzech klasach critical/major/minor, solve je naprawia). Znasz jego pełną
strukturę i kod. Chcę rozszerzyć ten ekosystem o tryb nocny: autonomiczną,
wielogodzinną sesję odpalaną każdego wieczoru na projektach Google Apps Script.

PROBLEM DO ROZWIĄZANIA
Projekty Apps Script pisane vibecodingiem od czasów GPT-3.5, wiele plików do 20k
linii. Każda dotychczasowa próba sprzątania kończyła się zepsuciem aplikacji.
Przyczyna: w Apps Script martwy kod jest niewykrywalny statycznie — funkcje są
wywoływane po nazwie ze stringów (ScriptApp.newTrigger("nazwa"),
createMenu().addItem("...", "nazwa"), google.script.run.nazwa() w plikach HTML,
handlery specjalne onOpen/onEdit/onInstall/doGet/doPost/onFormSubmit).

ZADANIE
Zaprojektuj i zaimplementuj tryb nocny (roboczo: pętla-noc) jako rozszerzenie
ekosystemu pętla-audyt/pętla-solve. Zdecyduj sam, czy to nowy skill-orkiestrator
wołający istniejące, czy nowy tryb wewnątrz pętli — wybierz architekturę spójną
z tym, co właśnie naprawiasz, i uzasadnij wybór.

WYMAGANIA TWARDE (nienegocjowalne):
1. Tryb w pełni unattended: zero pytań do użytkownika. Każda wątpliwość =
   pomiń + wpisz do raportu. Nigdy nie zgaduj.
2. Nic nie jest usuwane. Podejrzany martwy kod trafia do kwarantanny:
   plik _deprecated.gs, prefiks DEPRECATED_ w nazwie funkcji. Dzięki temu
   dynamiczne wywołanie da jawny błąd "function not found" zamiast cichej regresji.
3. Bramka bezpieczeństwa: naprawy (solve) i kwarantanna są dozwolone dla danego
   pliku/modułu TYLKO jeśli istnieją dla niego testy charakteryzujące i przechodzą
   przed zmianą oraz po niej. Bez testów — wyłącznie tryb audyt (raport).
4. Stan między sesjami: progress.json (co przerobione, per projekt per plik),
   żeby kolejne noce kontynuowały, a nie zaczynały od zera.
5. Każda sesja na branchu cleanup/<data>, commity atomowe (jedna kategoria zmian
   = jeden commit), zero push do main, zero clasp push. Deploy robię ręcznie rano.
6. Raport zbiorczy NIGHT_REPORT_<data>.md: co zrobiono, co pominięto i czemu,
   lista decyzji wymagających mojej ręcznej akceptacji, instrukcja revertu.

MODUŁY NOCNE (kolejność wg priorytetu, sesja przerabia ile zdąży):
A. Mapa zależności: graf wywołań funkcja→funkcja + wszystkie wywołania dynamiczne
   (triggery, menu, google.script.run z HTML) + entry pointy. Aktualizowana co noc,
   jest wejściem dla wszystkich pozostałych modułów.
B. Testy charakteryzujące: utrwalają OBECNE zachowanie (wejście X → wyjście Y),
   nie oceniają poprawności. Czysta logika JS testowana lokalnie w Node,
   SpreadsheetApp/GmailApp/PropertiesService za mockami.
C. JSDoc: każda funkcja dostaje opis, źródła wywołań (z mapy A), side-effecty.
D. Audyt pętla-audyt w klasyfikacji critical/major/minor + dodatkowo kategorie
   Apps Script: brak batch operacji (getValue w pętli vs getValues), hardkodowane
   ID arkuszy/maili, brak obsługi błędów wokół wywołań API, funkcje >200 linii,
   duplikacja logiki (SSOT/DRY).
E. Solve + kwarantanna martwego kodu — wyłącznie za bramką z punktu 3.
   Kwalifikacja do kwarantanny wymaga ŁĄCZNIE: zero referencji w .gs, zero w .html,
   nazwa nieobecna w żadnym stringu, brak na liście handlerów specjalnych,
   (opcjonalnie, jeśli istnieje runtime-log.json: brak wykonań w 30 dni).

DODATKOWO
Zaproponuj od siebie usprawnienia wynikające z pełnej znajomości pętla-audyt/solve,
których mogłem nie przewidzieć — np. mapowanie klas critical/major/minor na
kolejność napraw nocnych, reuse istniejących mechanizmów raportowania, integrację
z instrumentacją runtime (__touch() logujące wykonania funkcji do
PropertiesService jako osobny moduł przygotowawczy).

Zacznij od przedstawienia planu architektury (max 1 strona) — dopiero po moim OK
implementuj.

jak skonczysz caly solve to sie tym zajmiesz

======================================================================
== QUEUED PROMPT @ line 3854, 2026-06-10T04:15:35.701Z ==
======================================================================
UZUPEŁNIENIE DO PROJEKTU pętla-nocZanim zaczniesz implementację (albo jeśli już zacząłeś — uwzględnij w planie),rozszerzam zakres o dodatkowe moduły nocne F–K. To NIE jest osobny skill —wszystko wchodzi do tego samego orkiestratora, pod te same zasady twarde,
tę samą bramkę testową i ten sam progress.json. Sesja przerabia moduły
w kolejności priorytetu tyle, ile zdąży; resztę kontynuuje następnej nocy.

F. CANARY + DIFF SENTINEL (priorytet: zaraz po module B, odpalany KAŻDEJ nocy
   jako pierwszy krok wykonawczy):
   - Odpal pełen harness testów charakteryzujących na wszystkich projektach.
     Każdy fail = wpis na górze raportu z hashem commita, który prawdopodobnie
     go spowodował (git bisect po commitach od ostatniej zielonej nocy, jeśli tanio).
   - Pełen audyt (pętla-audyt, klasy critical/major/minor) odpalaj na kodzie
     zmienionym od poprzedniej sesji (git diff), żeby nowy dług był łapany
     w 24h, podczas gdy stary dług przerabiasz wg progress.json.

G. KONTRAKTY DANYCH KOD↔ARKUSZ:
   Znajdź wszystkie twarde indeksy kolumn (row[7], getRange("C2:C"), kolumny
   numeryczne w getRange) i zmapuj je na nagłówki arkuszy. Raportuj kandydatów
   do refaktoru na header-map (obiekt COL czytany z wiersza nagłówków).
   Sam refaktor — tylko za bramką testową, jako zadanie klasy major.

H. AUDYT KONFIGURACJI I SEKRETÓW:
   Hardkodowane ID arkuszy, adresy e-mail, URL-e webhooków, klucze API →
   raport + propozycja migracji do PropertiesService / jednego obiektu CONFIG.
   Dodatkowo odwrotnie: lista kluczy w PropertiesService nieczytanych nigdzie
   w kodzie (martwa konfiguracja).

I. POŁYKANE BŁĘDY:
   Puste catch, catch tylko z console.log, wywołania UrlFetchApp/MailApp/
   SpreadsheetApp/CalendarApp bez try. Raport + propozycja jednego wspólnego
   wrappera logującego do arkusza "Errors" (timestamp, projekt, funkcja, stack).
   Wdrożenie wrappera per plik — za bramką testową.

J. DUPLIKACJA MIĘDZY PROJEKTAMI:
   Porównuj projekty między sobą (nie tylko wewnątrz repo): te same/prawie te same
   funkcje utility w wielu projektach → raport kandydatów do wspólnej biblioteki
   GAS. WYŁĄCZNIE raport — wydzielanie biblioteki jest decyzją ręczną.

K. MODERNIZACJA SKŁADNI + ŻYWA DOKUMENTACJA (wypełniacz, najniższy priorytet):
   - var→const/let i równoważne zmiany zero-behavioral, tylko za bramką testową,
     osobny commit per plik.
   - Auto-aktualizacja ARCHITECTURE.md per projekt (entry pointy, triggery,
     przepływ danych, zależne arkusze/webhooki — generowane z mapy modułu A)
     oraz CHANGELOG.md z commitów.

KOLEJNOŚĆ DOCELOWA SESJI: F (zawsze) → A → B → C → I → G → D → E → H → J → K.
Jeśli F wykryje czerwone testy, sesja NIE wykonuje żadnych modułów zmieniających
kod (E, G-wdrożenie, I-wdrożenie, K) — tylko moduły raportowe, a fail testów
ląduje jako pierwsza pozycja raportu do mojej porannej decyzji.

ZASADA SPÓJNOŚCI: moduły F–K dziedziczą wszystkie wymagania twarde 1–6
z poprzedniego promptu. Wspólne reguły Apps Script (handlery specjalne,
wywołania dynamiczne) trzymaj w jednym pliku shared/ czytanym przez wszystkie
moduły — skill ma sam spełniać SSOT, który audytuje.

Zaktualizuj plan architektury o te moduły i pokaż mi go przed implementacją.

