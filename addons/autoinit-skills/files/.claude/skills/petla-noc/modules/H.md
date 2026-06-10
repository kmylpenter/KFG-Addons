# Moduł H — AUDYT KONFIGURACJI I SEKRETÓW (READ-ONLY, report-only)

Cel: (H1) hardkodowane ID/maile/webhooki/klucze → raport + propozycja migracji
do PropertiesService / obiektu CONFIG; (H2) odwrotnie — martwa konfiguracja:
klucze PropertiesService nieczytane nigdzie w kodzie.

## H1. Hardkody

1. Uruchom helper ssot: `python3 ~/.claude/skills/ssot-dry-audit/scripts/
   detect_duplicates.py <projekt> --allow-outside-cwd --output
   <projekt>/.petla-noc/reports/ssot-scan-<data>.json` (ścieżka POZYCYJNA;
   --allow-outside-cwd bo CWD orkiestratora zwykle nie jest przodkiem projektu)
   — konsumuj `duplicate_strings` z `secret_kind` (klucze API, tokeny) oraz
   długie stringi-ID.
2. Uzupełnij grep-ami wg gas-rules 9: ID arkuszy (kontekst openById/openByUrl),
   e-maile, URL-e webhooków. Deduplikuj z wynikami helpera.
3. Klasyfikacja per znalezisko: SECRET (klucz/token — w raporcie ZREDAGOWANE,
   pokazuj tylko prefiks 4 znaki + plik:linia) | ID-ZASOBU | EMAIL | URL.
4. Propozycja (RAPORT, nie zmiana!): per projekt jeden blok CONFIG —
   wylistuj proponowane klucze (`CONFIG.SHEET_RAPORTY`, `CONFIG.MAIL_BIURO`, ...)
   + szkic migracji (ile miejsc dotkniętych per klucz). Migracja = decyzja
   usera (sekcja DECYZJE) — moduł NIE zmienia kodu.

## H2. Martwa konfiguracja PropertiesService

1. Zbierz zbiory (grep po .gs):
   - SET: klucze z `setProperty('K'`/`setProperties({...})` (literalne),
   - GET: klucze z `getProperty('K'`,
   - dynamiczne klucze (zmienna zamiast literału) → odnotuj "klucze dynamiczne
     obecne — analiza niepełna" (doubt, nie zgaduj).
2. SET − GET = martwy zapis (kandydat do sprzątnięcia — RAPORT).
   GET − SET = klucz konfigurowany ręcznie/zewnętrznie → raport jako "wymagany
   klucz środowiska" (informacja, NIE błąd).
3. Realnych wartości NIE odczytasz offline (PropertiesService żyje w GAS) —
   nie próbuj; raport operuje na nazwach kluczy.

## Raport

- Tabela hardkodów (typ | wartość-zredagowana | wystąpienia | proponowany klucz CONFIG).
- Lista martwych zapisów + lista wymaganych kluczy środowiska.
- Sekcja DECYZJE: propozycja migracji per projekt (jedna pozycja zbiorcza).
- Criticale (jawny sekret w kodzie) → priority_queue + osobna pozycja na górze
  sekcji DECYZJI (rotacja klucza to działanie usera, nie skryptu).
