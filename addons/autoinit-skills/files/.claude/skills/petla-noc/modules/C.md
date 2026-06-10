# Moduł C — JSDOC (dokumentacja funkcji z mapy A)

Cel: każda funkcja dostaje JSDoc: co robi, skąd jest wywoływana (z map.json),
jakie ma side-effecty (arkusze/maile/properties/fetch).

## Wykonanie

1. Kandydaci: funkcje bez JSDoc (brak `/**` bezpośrednio nad definicją) —
   z map.json + grep. Priorytet: entry pointy i funkcje z priority_queue.
2. Per plik (sekwencyjnie, główny kontekst — to mutacja): dla każdej funkcji
   wygeneruj blok:

```js
/**
 * [1-2 zdania CO robi — z lektury ciała, nie zgadywane.]
 * Wywoływana przez: onOpen (menu "Raporty"), wyslijRaport()   ← z map.json called_by/dynamic_refs
 * Side-effects: czyta arkusz "Dane"; wysyła e-mail (MailApp); zapisuje ScriptProperties["X"]
 * @param {string} name - [z użycia w ciele; niepewny typ → {*}]
 * @returns {number[]} [z return statements; brak return → @returns {void}]
 */
```

3. Nie wymyślaj: niejasny cel funkcji → opis "TODO(noc): cel niejasny — [co
   widać z kodu]" + wpis do raportu (sekcja Pominięte). Side-effecty WYŁĄCZNIE
   z faktycznych wywołań API w ciele (uses_gas_api z map.json + lektura).
4. **Walidacja comment-only-diff (bramka modułu C, kanon: SKILL.md BRAMKA):**
   po edycji pliku `git diff -U0 -- <plik>` — KAŻDA dodana linia musi być
   wewnątrz bloku `/** ... */` lub pusta; ŻADNA linia nie usunięta/zmieniona.
   Naruszenie → `git checkout -- <plik>` + raport. Jeśli projekt ma testy:
   dodatkowo harness green po edycji.
5. Commit kategorii `jsdoc` per projekt (jedna noc = jeden commit jsdoc).

## Zasady

- Dozwolony w RED MODE (lista wyłączeń usera nie obejmuje C; komentarze nie
  zmieniają semantyki) — comment-only-diff obowiązuje ZAWSZE.
- Pliki >2k linii: edytuj per funkcja (Edit ze ścisłym kontekstem), nie przepisuj bloków.
- Istniejący JSDoc: NIE nadpisuj — uzupełnij brakujące sekcje (Wywoływana przez/
  Side-effects) tylko jeśli ich nie ma.
