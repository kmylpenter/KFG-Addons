# HANDOFF — <feature-id>

> Wygenerowane przez `/domknij` (stan: **CZĘŚCIOWO gotowy**) dnia `<YYYY-MM-DD>`, sesja `<id>`.
> Następna sesja: PRZECZYTAJ to na starcie, żeby wiedzieć, które testy są WIP (łamanie WIP ≠ regresja).

## ✅ DZIAŁA (zapięte jako STABLE — kontrakt)
Testy w `.petla-noc/tests/` — wchodzą do canary petla-noc; złamanie = REGRESJA (alarm).

- `<funkcja/flow>` — `<tests/sealed_<id>.test.js>` — poziom: `<function|flow>` — potwierdzone: `<co user przeklikał>`

## 🚧 WIP (zapięte jako tymczasowe — zrzut, NIE kontrakt)
Testy w `.petla-noc/tests-wip/` — POZA canary; łamanie ich przy dalszym rozwoju ≠ regresja.
Gdy następna sesja je złamie: `/domknij` (lub główny agent) ZAPYTA „aktualizować pod nowe
zachowanie czy regresja?", nie zaalarmuje.

- `<funkcja/flow>` — `<tests-wip/sealed_<id>.test.js>` — dlaczego WIP: `<np. logika jeszcze się zmieni>`

### Case'y NIEpotwierdzone (`confirmed:false`)
Dopisane z odczytu kodu, NIE z werdyktu usera — hipotezy, nie kontrakt:
- `<nazwa case'a>` — `<plik>`

## ⛔ JESZCZE NIEZROBIONE
- `<co zostało do zbudowania>`

## ↩️ GDZIE WRÓCIĆ
- Pliki: `<lista>`
- Następny krok: `<konkret>`
- Domknięcie: gdy feature gotowy → `/domknij` → „w pełni gotowy" → testy WIP tego feature'a
  AWANSUJĄ do STABLE (snapshot → kontrakt).

## 📊 POKRYCIE (uczciwość — zasada twarda #3)
- **Pełne** (czysta logika JS): `<funkcje>`
- **Częściowe** (za mockami — logika wokół wywołania GAS, nie efekt w arkuszu/mailu): `<funkcje>`
- **Poza zasięgiem** (live UrlFetch / triggery / >300 linii / JS klienta w `index.html`): `<co>`
