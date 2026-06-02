# ADB pairing z NATYWNEGO Termuksa (poza PRoot)

**Dlaczego:** adb uruchamiany pod PRootem (sesja Claude) wywala „protocol fault
(couldn't read status message)" przy parowaniu — TLS handshake pada pod PRootem.
Kanoniczne poradniki Termuksa parują adb **natywnie**. Serwer adb wystartowany
natywnie obsłuży parowanie, a czytaj w PRoot użyje TEGO SAMEGO serwera (localhost:5037).

## Kroki — WSZYSTKO w zwykłej sesji Termuksa, NIE w Claude/PRoot

1. Otwórz **NOWĄ sesję Termuksa**: przeciągnij od lewej krawędzi ekranu → „New session".
   To jest natywny Termux (jeszcze nie wszedłeś w PRoot — nie ma promptu z projektem).

2. Wystartuj świeży, natywny serwer adb:
   ```
   adb kill-server
   adb start-server
   ```

3. Na telefonie: wyłącz i włącz Debugowanie bezprzewodowe (świeży stan), potem otwórz
   „Sparuj urządzenie za pomocą kodu parowania". Działaj szybko (okienko żyje ~minutę).

4. Sparuj — **port parowania** + **kod** z okienka (uważaj na pełny port, 5 cyfr!):
   ```
   adb pair 127.0.0.1:PORT_PAROWANIA KOD
   ```
   przykład: `adb pair 127.0.0.1:40169 295572`

5. Po „Successfully paired" — połącz portem z **głównego** ekranu „Adres IP i port":
   ```
   adb connect 127.0.0.1:PORT_POLACZENIA
   ```

6. Sprawdź:
   ```
   adb devices
   ```
   Ma pokazać urządzenie ze statusem `device` (nie `unauthorized`).

7. Napisz mi **„sparowane w Termuksie"**. Czytaj (PRoot) sięgnie do tego samego serwera
   adb i przepnę czytnik klawiszy z Shizuku na adb (niski lag).

## Jeśli i to da „protocol fault"
Wtedy zostaje **restart telefonu** (czyści głęboki stan TLS — tak radzi większość
poradników), po restarcie powtórz kroki 2–6. Restart ubije tę sesję Claude, ale
transkrypt zostaje i wznowimy.
