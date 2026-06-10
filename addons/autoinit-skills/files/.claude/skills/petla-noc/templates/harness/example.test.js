// PRZYKŁAD testu charakteryzującego (moduł B kopiuje ten wzorzec).
// Test utrwala OBECNE zachowanie — wartości oczekiwane pochodzą z ANALIZY KODU,
// nie z oceny "jak powinno być". Jeden plik testowy gate'uje jeden plik źródłowy.
"use strict";

module.exports = {
  file: "Kod.gs", // który plik źródłowy te testy bramkują (progress.json files[...]got tests)
  tests: [
    {
      name: "parseKwota: '1 234,56 zł' -> 1234.56 (czysta logika, bez fixtures)",
      fixtures: {},
      run: (g, state, assert) => {
        assert.equal(g.parseKwota("1 234,56 zł"), 1234.56);
        assert.equal(g.parseKwota(""), 0); // utrwalamy obecny fallback
      },
    },
    {
      name: "policzSume: czyta arkusz Dane przez getValues i sumuje kolumnę Kwota",
      fixtures: {
        sheets: { "*": { "Dane": [["Imie", "Kwota"], ["A", 10], ["B", 32]] } },
      },
      run: (g, state, assert) => {
        assert.equal(g.policzSume(), 42);
      },
    },
    {
      name: "wyslijRaport: wysyła jeden mail z sumą (side-effect przez mock MailApp)",
      fixtures: {
        sheets: { "*": { "Dane": [["Imie", "Kwota"], ["A", 10], ["B", 32]] } },
        properties: { MAIL_TO: "biuro@example.com" },
      },
      run: (g, state, assert) => {
        g.wyslijRaport();
        assert.equal(state.sentEmails.length, 1);
        assert.equal(state.sentEmails[0].args[0], "biuro@example.com");
        assert.ok(String(state.sentEmails[0].args[2]).includes("42"));
      },
    },
  ],
};
