# Parowanie ADB dla czytaj — Pixel 9 Pro XL (Android 16, PL)

**Cel:** połączyć Termux z lokalnym ADB telefonu, żeby czytnik klawiszy działał
błyskawicznie i bez zamarzania (zamiast mostka Shizuku z lagiem ~11 s).

**Warunek:** Debugowanie bezprzewodowe wymaga **włączonego Wi-Fi**. Włącz Wi-Fi
przed startem. (Łączymy się przez localhost, więc IP z ekranu nie jest potrzebne —
liczą się tylko PORTY i kod.)

---

## A. Na telefonie

1. **Opcje programisty** (jeśli jeszcze nie masz):
   Ustawienia → **Informacje o telefonie** → stuknij **„Numer kompilacji"** 7 razy
   (poprosi o PIN). Pojawi się „Jesteś teraz programistą".

2. Ustawienia → **System** → **Opcje programisty** → włącz **„Debugowanie
   bezprzewodowe"** (przełącznik). W okienku potwierdź **„Zezwól"**.

3. Stuknij w **napis** „Debugowanie bezprzewodowe" (wejdź w jego ekran).
   Na głównym ekranie zobaczysz **„Adres IP i port"**, np. `192.168.0.12:39123`.
   → To jest **PORT POŁĄCZENIA** (connect), tutaj `39123`.

4. Stuknij **„Sparuj urządzenie za pomocą kodu parowania"**.
   Pokaże się **6-cyfrowy kod** + drugi **„Adres IP i port"**, np. `192.168.0.12:43251`.
   → To jest **PORT PAROWANIA** (pair), tutaj `43251` — **INNY** niż connect.
   ⚠️ **Zostaw to okienko otwarte** — kod znika po zamknięciu.

---

## B. Połączenie — najprościej: podaj mi 3 wartości

Po krokach A (z **otwartym** okienkiem „Sparuj…") przeczytaj z ekranu i napisz mi
**w jednej wiadomości** trzy rzeczy:
- **PORT PAROWANIA** — z okienka „Sparuj…" (krok 4), np. `43251`
- **6-cyfrowy KOD** — z okienka „Sparuj…" (krok 4)
- **PORT POŁĄCZENIA** — z głównego ekranu „Debugowanie bezprzewodowe" (krok 3), np. `39123`

Przykład wiadomości: **„pair 43251, kod 123456, connect 39123"**.
Ja od razu sparuję i połączę (`adb pair` + `adb connect` przez localhost) i potwierdzę.
⚠️ Trzymaj okienko „Sparuj…" **otwarte** aż napiszę „sparowane" — kod szybko wygasa.

> Czemu nie odpalasz skryptu sam przez Claude: `setup-adb-pairing.sh` jest
> interaktywny (pyta o porty), a uruchomiony przez Claude nie dostanie Twoich
> wpisów. Jeśli wolisz samodzielnie — odpal go w **osobnym, czystym Termuksie**
> (poza Claude): `bash ~/.claude/hooks/czytaj/setup-adb-pairing.sh`.

---

## C. Po połączeniu

Gdy potwierdzę „sparowane + połączone", przepnę czytnik klawiszy z Shizuku na ADB
(niski lag, bez zamarzania), z **automatycznym fallbackiem na Shizuku** gdy nie ma
Wi-Fi — w aucie dalej po staremu, a w domu na Wi-Fi błyskawicznie.

### Najczęstsze pomyłki
- Pomylenie dwóch portów (pair ≠ connect). Pair port jest jednorazowy i wygasa.
- Kod wygasł → otwórz okienko „Sparuj…" jeszcze raz (nowy kod, nowy pair port).
- Wi-Fi wyłączone → „Debugowanie bezprzewodowe" się rozłącza.
