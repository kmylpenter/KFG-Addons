// PRZYKŁAD testu logiki klienta (FAZA POKRYCIA / B-client kopiuje ten wzorzec).
// Charakteryzuje LOGIKĘ funkcji z <script> w .html — wartości oczekiwane z ANALIZY KODU,
// nie z oceny "jak powinno być". DOM + google.script.run = shim (client-mocks.js).
// Czysty glue (input→server→DOM bez logiki) → warstwa SMOKE, NIE tutaj.
"use strict";

module.exports = {
  file: "index.html", // który plik .html dostarcza <script> (jego inline-skrypty są ładowane)
  tests: [
    {
      name: "validateAmount: '12,5' -> 12.5; '-3' -> null (czysta logika)",
      fixtures: {},
      run: (g, state, assert) => {
        assert.equal(g.validateAmount("12,5"), 12.5);
        assert.equal(g.validateAmount("-3"), null); // utrwalamy obecny fallback
      },
    },
    {
      name: "submitForm: złe wejście -> alert, zero wywołań serwera",
      fixtures: { dom: { "#amount": { value: "abc" } } },
      run: (g, state, assert) => {
        g.submitForm();
        assert.equal(state.alerts.length, 1);
        assert.equal(state.serverCalls.length, 0);
      },
    },
    {
      name: "submitForm: poprawne wejście -> saveAmount(10); success handler pisze do #status",
      fixtures: { dom: { "#amount": { value: "10" }, "#status": {} }, server: { saveAmount: "OK" } },
      run: (g, state, assert) => {
        g.submitForm();
        assert.equal(state.serverCalls.length, 1);
        assert.equal(state.serverCalls[0].fn, "saveAmount");
        assert.equal(state.serverCalls[0].args[0], 10);
        assert.equal(g.document.getElementById("status").textContent, "OK"); // success handler resolved synchronously
      },
    },
  ],
};
