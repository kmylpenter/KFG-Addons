# Moduł I — POŁYKANE BŁĘDY (raport zawsze; wdrożenie wrappera per plik za bramką)

Cel: znaleźć miejsca, gdzie błędy znikają bez śladu, i (opcjonalnie, za bramką)
wdrożyć JEDEN wspólny wrapper `withErrorLog` logujący do arkusza "Errors"
(timestamp, projekt, funkcja, message, stack). Wzorzec wrappera: gas-rules 8 (SSOT).

## I-raport (READ-ONLY, subagent per projekt, równolegle; działa też w RED)

Wykrywanie (definicje wzorców: gas-rules 8):
1. puste `catch (e) {}` (także z samym komentarzem),
2. catch-tylko-log (`Logger.log` / `console.log` i nic więcej — błąd zjedzony),
3. wywołania `UrlFetchApp|MailApp|GmailApp|SpreadsheetApp|CalendarApp` poza
   jakimkolwiek `try` (heurystyka per funkcja: czy linia wywołania jest objęta
   try-blokiem w tej funkcji; wywołania w funkcjach wołanych z try NIE licz
   podwójnie — zaznacz "objęte pośrednio" jeśli WSZYSCY callerzy mają try).
Per trafienie: plik:linia, funkcja, typ (empty-catch / log-only / no-try),
severity: empty-catch=major, log-only=major, no-try=minor (chyba że funkcja
to entry point/trigger → major; krytyczne przepływy — wysyłka maili, zapisy
finansowe — critical wg osądu z kontekstu).

## I-wdrożenie (opcjonalne; bramka pełna: testy green, nie-RED, branch)

1. Warunek wstępny: projekt MA obiekt CONFIG z ERRORS_SSID albo aktywny
   spreadsheet (wrapper musi wiedzieć, gdzie logować — gas-rules 8). Brak →
   tylko raport + DECYZJA ("wskaż arkusz Errors").
2. Per plik (1 plik = 1 commit `error-wrapper`):
   a. wstaw definicję `withErrorLog` RAZ na projekt (nowy plik `_errors.gs` —
      nazwa z prefiksem podkreślenia, jak _deprecated);
   b. opakuj ciała funkcji z trafieniami typu no-try:
      `function f(a,b) { return withErrorLog("f", function () { ...oryginalne ciało... }); }`
      — zero zmian w samym ciele; funkcje używające `this`/`arguments` w ciele
      → report-only (gas-rules 8: opakowanie zmieniłoby ich semantykę);
   c. empty-catch / log-only: NIE zmieniaj automatycznie semantyki (mogły być
      celowe!) → te idą do DECYZJI raportu z propozycją (`+ appendRow do Errors`
      / `+ throw`); wyjątek: jeśli komentarz w kodzie mówi wprost "ignore" →
      zostaw, odnotuj jako celowe.
3. Po pliku: harness green → commit; fail → rollback + raport.
4. Top-level code NIE opakowuj (zmiana czasu wykonania globali — ryzyko); raportuj.

## Raport

Tabela trafień + per plik status: wrapped(hash) / report-only / DECYZJA.
Wrapper wdrożony → przypomnienie w raporcie: arkusz "Errors" powstanie przy
pierwszym błędzie po wejściu wrappera na produkcję — ale klikanie po linku
NOCNYM też może go utworzyć (wrapper żyje w wersji przypiętej do linku).
