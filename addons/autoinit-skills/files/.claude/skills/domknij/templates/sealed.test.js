// SZABLON testu ZAPIĘTEGO (/domknij kopiuje ten wzorzec).
//
// Różnica wobec petla-noc templates/harness/example.test.js (test B, retrospektywny):
//   • B utrwala zachowanie wyczytane Z KODU (utrwala też ciche błędy).
//   • TEN test utrwala zachowanie, które USER JAWNIE POTWIERDZIŁ w sesji (przeklikał).
//
// Harness czyta TYLKO `module.exports.file` i `module.exports.tests` — pola `sealed`
// (poziom pliku) i `confirmed` (poziom case'a) są przez harness IGNOROWANE (kompatybilne
// wstecz), a służą: prowenancji w raporcie petla-noc, dojrzewaniu WIP→stable i uczciwości
// pokrycia. NIE usuwaj ich.
"use strict";

module.exports = {
  // Który plik źródłowy te testy bramkują (progress.json files[...], mapowanie do bramki).
  file: "Code.gs",

  // ── METADANE ZAPIĘCIA (czyta /domknij i petla-noc; harness ignoruje) ──────────
  sealed: {
    status: "stable",            // "stable" = kontrakt (katalog tests/); "wip" = zrzut (tests-wip/)
    accepted: "2026-06-14",      // data akceptacji usera (YYYY-MM-DD)
    session: "2026-06-14-feature-x", // krótki identyfikator sesji
    level: "mixed",              // "function" (wejście→wyjście) | "flow" (np. doPost→200+wiersz) | "mixed"
    feature: "feature-x",        // feature-id (kebab) — klucz w manifest.json
    coverage: {                  // 3 kubełki uczciwości pokrycia (zasada twarda #3)
      full: ["parseKwota"],                  // czysta logika JS — dokładny kontrakt
      mock_gated: ["zapiszWiersz"],          // za mockami — logika wokół wywołania GAS, nie sam efekt
      out_of_scope: ["index.html <script> (klient)", "wyslijRaportNaZywo (live UrlFetch)"],
    },
  },

  tests: [
    {
      // POTWIERDZONY przez usera (przeklikał: kwota z formularza parsuje się tak).
      name: "parseKwota: '1 234,56 zł' -> 1234.56 (potwierdzone w sesji)",
      confirmed: true,           // true = werdykt usera; false = dopisane z odczytu kodu (tylko tests-wip/)
      fixtures: {},
      run: (g, state, assert) => {
        assert.equal(g.parseKwota("1 234,56 zł"), 1234.56);
      },
    },
    {
      // FLOW potwierdzony: user przekliknął zapis i zobaczył wiersz w arkuszu.
      // Bramka łapie LOGIKĘ wokół zapisu (że woła appendRow z właściwym wierszem),
      // nie sam efekt w prawdziwym arkuszu — to mock (coverage.mock_gated).
      name: "zapiszWiersz: dopisuje [data, kwota] do arkusza Dane (flow, mock)",
      confirmed: true,
      fixtures: {
        sheets: { "*": { "Dane": [["Data", "Kwota"]] } },
        properties: { ARKUSZ: "Dane" },
      },
      run: (g, state, assert) => {
        g.zapiszWiersz("2026-06-14", 1234.56);
        const dane = state.spreadsheets["*"].getSheetByName("Dane").getDataRange().getValues();
        assert.equal(dane.length, 2);            // nagłówek + 1 dopisany
        assert.equal(dane[1][1], 1234.56);
      },
    },
    {
      // PRZYKŁAD case'a NIEpotwierdzonego (robustness z odczytu kodu).
      // confirmed:false ⇒ ten case wolno trzymać WYŁĄCZNIE w tests-wip/, nigdy w kontrakcie
      // stabilnym, i MUSI być wymieniony w raporcie jako „hipoteza z kodu".
      name: "parseKwota: '' -> 0 (NIEpotwierdzone — fallback z odczytu kodu)",
      confirmed: false,
      fixtures: {},
      run: (g, state, assert) => {
        assert.equal(g.parseKwota(""), 0);
      },
    },
  ],
};
