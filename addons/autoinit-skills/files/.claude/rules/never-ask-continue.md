# Never Ask to Continue

## Problem

Po kompakcji kontekstu Claude "zapomina" instrukcję użytkownika "pracuj aż skończysz" i wraca do domyślnego zachowania - pytanie o pozwolenie na kontynuację.

## Zasada

**NIGDY nie pytaj o kontynuację podczas wykonywania skilli lub długich tasków.**

### Zakazane pytania

```
❌ "Czy kontynuować?"
❌ "Pozostało X do zrobienia, czy mam dalej?"
❌ "Chcesz żebym kontynuował?"
❌ "Czy mogę przejść do następnej fazy/iteracji?"
❌ "Mam kontynuować z pozostałymi taskami?"
```

### Prawidłowe zachowanie

```
✅ Kontynuuj automatycznie do końca
✅ Raportuj postęp (np. "Task 3/10 done") ale NIE PYTAJ
✅ Zatrzymaj się TYLKO przy błędach wymagających decyzji użytkownika
✅ User może przerwać w każdej chwili przez Ctrl+C
```

## Logika

| Sytuacja | Akcja |
|----------|-------|
| Pozostały taski do zrobienia | Kontynuuj |
| Faza zakończona, jest następna | Przejdź do następnej |
| Iteracja zakończona, nie ma consensus | Kontynuuj iteracje |
| Błąd krytyczny | Zatrzymaj i opisz problem |
| Nie wiesz czy kontynuować | **KONTYNUUJ** |

## Wyjątki (kiedy MOŻNA pytać)

1. **Błąd blokujący** - np. brak pliku, permission denied
2. **Decyzja architektoniczna** - np. "Znalazłem 2 podejścia, które wybrać?"
3. **User explicite prosił o potwierdzenie** - np. "przed każdym commitem pytaj"

## Dlaczego to ważne

- Skille jak `/loop solve` mogą trwać 30-60 minut
- Kompakcja kontekstu usuwa instrukcje użytkownika
- User powiedział "pracuj aż skończysz" - szanuj to
- Przerywanie co 5 minut zabija produktywność

---

## 🚨 ENFORCEMENT: Self-Check przed zakończeniem

**ZANIM napiszesz "podsumowanie", "summary", lub "zakończone":**

1. Wywołaj `TaskList()`
2. Sprawdź: czy `pending > 0`?

**CHECK:**
- pending > 0 → **NIE MOŻESZ ZAKOŃCZYĆ**. Wróć do pracy.
- pending == 0 → Możesz napisać summary.

**Nie pisz "Podsumowanie" gdy masz pending taski!**

---

## Red Flags (jeśli to piszesz, ZATRZYMAJ SIĘ)

Te frazy oznaczają że łamiesz zasadę:

- "Podsumowanie sesji" (gdy pending > 0)
- "Dotychczasowy postęp" (sugeruje przerwanie)
- "Możemy kontynuować później"
- "Pozostałe do zrobienia" (w kontekście zakończenia)

Jeśli zauważysz że to piszesz → sprawdź TaskList → jeśli pending > 0 → KONTYNUUJ PRACĘ
