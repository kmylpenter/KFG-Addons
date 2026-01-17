#!/usr/bin/env python3
"""
CCv3 Polish Translation - V6 Fixes
Naprawia wszystkie problemy z raportu testowego.

HIGH:
- H1: intentPatterns dla "zapisz" w commit/remember/continuity_ledger
- H2: "kończę/wznów" w handoff skills
- H3: "write tests" regresja EN

MEDIUM:
- M1: Polski slang: wrzuć, ogarnij, schrzaniło, zmergeuj
- M2: Naturalne formy: przegląd, przyczyna, ryzyka, przeprowadź
- M3: Keywords research: użycia funkcji, napisz dokumentację, napisz testy
- M4: intentPatterns dla "zrób" z kontekstem
"""

import json
from pathlib import Path

def load_rules(path: Path) -> dict:
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)

def save_rules(rules: dict, path: Path):
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(rules, f, ensure_ascii=False, indent=4)

def add_keywords(rules: dict, section: str, skill: str, keywords: list):
    """Dodaj keywords do skilla (bez duplikatów)"""
    if skill in rules.get(section, {}):
        existing = rules[section][skill].get('promptTriggers', {}).get('keywords', [])
        for kw in keywords:
            if kw not in existing:
                existing.append(kw)
        rules[section][skill]['promptTriggers']['keywords'] = existing

def add_intent_patterns(rules: dict, section: str, skill: str, patterns: list):
    """Dodaj intentPatterns do skilla (bez duplikatów)"""
    if skill in rules.get(section, {}):
        existing = rules[section][skill].get('promptTriggers', {}).get('intentPatterns', [])
        for p in patterns:
            if p not in existing:
                existing.append(p)
        rules[section][skill]['promptTriggers']['intentPatterns'] = existing

def fix_high_issues(rules: dict):
    """Napraw wszystkie HIGH priority issues"""

    # H1: intentPatterns dla "zapisz"
    print("  H1: Dodaję intentPatterns dla 'zapisz'...")

    # commit - zapisz tylko w kontekście git
    add_intent_patterns(rules, 'skills', 'commit', [
        "(zapisz|zachowaj).*(zmiany|kod|prace|pracę).*?(git|repo|commit)",
        "(zapisz|zachowaj).*(do|w).*(repo|git|repozytorium)",
        "git.*(zapisz|save)",
    ])

    # remember - zapisz w kontekście pamięci
    add_intent_patterns(rules, 'skills', 'remember', [
        "(zapisz|zachowaj|zapamiętaj).*(to|tę|ten).*(pamięci|pamieci|memory)",
        "(zapisz|zachowaj).*(wzorzec|pattern|learning|nauczka)",
        "(zapamiętaj|remember).*(na przyszłość|na przyszlosc)",
    ])

    # continuity_ledger - zapisz w kontekście stanu/kontekstu
    add_intent_patterns(rules, 'skills', 'continuity_ledger', [
        "(zapisz|zachowaj).*(stan|state|kontekst|context)",
        "(zapisz|zachowaj).*(przed|before).*(compact|kompakcją|kompakcja)",
        "(zapisz|zachowaj).*(ledger|księgę|ksiege)",
    ])

    # H2: kończę/wznów w handoff skills
    print("  H2: Dodaję 'kończę/wznów' do handoff skills...")

    add_keywords(rules, 'skills', 'create_handoff', [
        "kończę",
        "kończe",
        "koncze",
        "kończymy",
        "konczymy",
        "na dziś",
        "na dzis",
        "na dzisiaj",
        "przerwa",
        "przerywam",
        "zamykam sesję",
        "zamykam sesje",
        "do jutra",
        "do następnego razu",
        "do nastepnego razu",
        "wystarczy na dziś",
        "wystarczy na dzis",
        "zostawiam na później",
        "zostawiam na pozniej",
    ])

    add_intent_patterns(rules, 'skills', 'create_handoff', [
        "(kończ|koncz|kończy|konczy).*(na dziś|na dzis|sesję|sesje|pracę|prace)",
        "(przeryw|zostawia).*(na|do).*(później|pozniej|jutra)",
        "(zamyk|końc).*(sesj|prac)",
    ])

    add_keywords(rules, 'skills', 'resume_handoff', [
        "wznów",
        "wznow",
        "wznawiaj",
        "wznowienie",
        "wznawiam",
        "kontynuuj sesję",
        "kontynuuj sesje",
        "kontynuujemy",
        "wczorajsza sesja",
        "poprzednia sesja",
        "gdzie skończyliśmy",
        "gdzie skonczylismy",
        "gdzie stanęliśmy",
        "gdzie stanelismy",
        "co było robione",
        "co bylo robione",
        "ostatnia sesja",
    ])

    add_intent_patterns(rules, 'skills', 'resume_handoff', [
        "(wznów|wznow|wznawia|kontynuuj).*(sesj|prac|handoff)",
        "(gdzie|co).*(skończy|skonczy|stane|było|bylo).*(robione|wczoraj|ostatnio)",
        "(poprzedni|wczorajsz|ostatni).*(sesj|prac|handoff)",
    ])

    # H3: "write tests" regresja EN
    print("  H3: Dodaję 'write tests' (regresja EN)...")

    add_keywords(rules, 'skills', 'test', [
        "write tests",
        "write unit tests",
        "write test",
        "create tests",
        "add tests",
        "napisz testy",
        "napisz test",
        "dodaj testy",
        "stwórz testy",
        "stworz testy",
        "testy jednostkowe",
        "testy integracyjne",
        "unit testy",
    ])

    add_intent_patterns(rules, 'skills', 'test', [
        "(write|create|add|napisz|dodaj|stwórz|stworz).*(test|testy)",
        "(testy|tests).*(jednostkow|integracy|unit)",
    ])

def fix_medium_issues(rules: dict):
    """Napraw wszystkie MEDIUM priority issues"""

    # M1: Polski slang developerski
    print("  M1: Dodaję polski slang developerski...")

    # commit - slang
    add_keywords(rules, 'skills', 'commit', [
        "wrzuć",
        "wrzuc",
        "wypchnij",
        "pushuj",
        "pushnij",
        "wrzuć na gita",
        "wrzuc na gita",
        "wypchnij zmiany",
        "zmergeuj",
        "zmerguj",
        "merge'uj",
        "połącz branch",
        "polacz branch",
    ])

    add_intent_patterns(rules, 'skills', 'commit', [
        "(wrzuć|wrzuc|wypchnij|push).*(git|repo|branch|zmiany)",
        "(zmerge|zmerg|merge|połącz|polacz).*(branch|gałąź|galaz)",
    ])

    # fix - slang
    add_keywords(rules, 'skills', 'fix', [
        "schrzaniło się",
        "schrzanilo sie",
        "zepsuło się",
        "zepsulo sie",
        "padło",
        "padlo",
        "wykrzaczyło",
        "wykrzaczylo",
        "sypie się",
        "sypie sie",
        "się wysypało",
        "sie wysypalo",
        "crashuje",
        "crash",
        "wybuchło",
        "wybuchlo",
    ])

    add_intent_patterns(rules, 'skills', 'fix', [
        "(schrzani|zepsu|pad|wykrzacz|wysypa|crash|wybuch).*(się|sie|ło|lo)",
        "(coś|cos).*(się|sie).*(schrzani|zepsu|wysypa)",
    ])

    # refactor - slang
    add_keywords(rules, 'skills', 'refactor', [
        "ogarnij",
        "ogarnąć",
        "ogarnac",
        "posprzątaj",
        "posprzataj",
        "burdel",
        "bajzel",
        "syf",
        "ogarnij ten kod",
        "posprzątaj kod",
        "posprzataj kod",
        "wyczyść",
        "wyczysc",
    ])

    add_intent_patterns(rules, 'skills', 'refactor', [
        "(ogarnij|ogarn|posprzątaj|posprzataj|wyczyść|wyczysc).*(kod|to|ten|moduł|modul)",
        "(burdel|bajzel|syf).*(w|kod)",
        "(kod|ten).*(burdel|bajzel|syf)",
    ])

    # M2: Naturalne polskie formy
    print("  M2: Dodaję naturalne polskie formy...")

    # review - przegląd
    add_keywords(rules, 'skills', 'review', [
        "przegląd",
        "przeglad",
        "przegląd kodu",
        "przeglad kodu",
        "zrób przegląd",
        "zrob przeglad",
        "przejrzyj",
        "przejrzyj kod",
        "sprawdź kod",
        "sprawdz kod",
        "oceń kod",
        "ocen kod",
    ])

    add_intent_patterns(rules, 'skills', 'review', [
        "(zrób|zrob|wykonaj).*(przegląd|przeglad|review)",
        "(przejrzyj|sprawdź|sprawdz|oceń|ocen).*(kod|PR|pull request|zmiany)",
    ])

    # debug - przyczyna
    add_keywords(rules, 'skills', 'debug', [
        "przyczyna",
        "przyczyna błędu",
        "przyczyna bledu",
        "znajdź przyczynę",
        "znajdz przyczyne",
        "dlaczego nie działa",
        "dlaczego nie dziala",
        "co jest nie tak",
        "co poszło nie tak",
        "co poszlo nie tak",
        "skąd błąd",
        "skad blad",
    ])

    add_intent_patterns(rules, 'skills', 'debug', [
        "(znajdź|znajdz|zlokalizuj|ustal).*(przyczyn|powód|powod)",
        "(dlaczego|czemu|skąd|skad).*(nie działa|nie dziala|błąd|blad|error)",
        "(co|skąd|skad).*(poszło|poszlo|jest).*(nie tak|źle|zle)",
    ])

    # premortem - ryzyka
    add_keywords(rules, 'skills', 'premortem', [
        "ryzyka",
        "ryzyko",
        "zagrożenia",
        "zagrozenia",
        "co może pójść źle",
        "co moze pojsc zle",
        "co może się zepsuć",
        "co moze sie zepsuc",
        "potencjalne problemy",
        "możliwe problemy",
        "mozliwe problemy",
    ])

    add_intent_patterns(rules, 'skills', 'premortem', [
        "(jakie|co).*(ryzyk|zagrożeni|zagrozeni|może|moze).*(pójść|pojsc|źle|zle)",
        "(potencjaln|możliw|mozliw).*(problem|ryzyk|zagrożeni)",
    ])

    # migrate - przeprowadź
    add_keywords(rules, 'skills', 'migrate', [
        "przeprowadź",
        "przeprowadz",
        "przeprowadź migrację",
        "przeprowadz migracje",
        "wykonaj migrację",
        "wykonaj migracje",
        "zmigruj",
        "przenieś",
        "przenies",
    ])

    add_intent_patterns(rules, 'skills', 'migrate', [
        "(przeprowadź|przeprowadz|wykonaj|zrób|zrob).*(migracj|migration)",
        "(zmigruj|przenieś|przenies).*(baz|dane|kod|system)",
    ])

    # nia-docs - przeszukaj
    add_keywords(rules, 'skills', 'nia-docs', [
        "przeszukaj dokumentację",
        "przeszukaj dokumentacje",
        "przeszukaj docs",
        "szukaj w dokumentacji",
        "szukaj w docs",
        "znajdź w dokumentacji",
        "znajdz w dokumentacji",
    ])

    add_intent_patterns(rules, 'skills', 'nia-docs', [
        "(przeszukaj|szukaj|znajdź|znajdz).*(dokumentacj|docs|api reference)",
    ])

    # M3: Keywords research skills
    print("  M3: Dodaję keywords dla research skills...")

    # ast-grep-find - użycia funkcji
    add_keywords(rules, 'skills', 'ast-grep-find', [
        "użycia funkcji",
        "uzycia funkcji",
        "wywołania funkcji",
        "wywolania funkcji",
        "gdzie jest używane",
        "gdzie jest uzywane",
        "kto używa",
        "kto uzywa",
        "znajdź wywołania",
        "znajdz wywolania",
        "znajdź użycia",
        "znajdz uzycia",
        "referencje do",
    ])

    add_intent_patterns(rules, 'skills', 'ast-grep-find', [
        "(znajdź|znajdz|pokaż|pokaz).*(użyci|uzyci|wywołani|wywolani).*(funkcj|metod|klas)",
        "(kto|gdzie|co).*(używa|uzywa|wywołuje|wywoluje)",
        "(referencje|odwołania|odwolania).*(do|funkcj|metod)",
    ])

    # github-search - PR
    add_keywords(rules, 'skills', 'github-search', [
        "sprawdź PR",
        "sprawdz PR",
        "pokaż PR",
        "pokaz PR",
        "pull request #",
        "issue #",
        "github issue",
        "otwarte PR",
        "otwarte issues",
    ])

    add_intent_patterns(rules, 'skills', 'github-search', [
        "(sprawdź|sprawdz|pokaż|pokaz|znajdź|znajdz).*(PR|pull request|issue).*#?[0-9]*",
        "(otwarte|open).*(PR|pull request|issue)",
    ])

    # M4: intentPatterns dla "zrób" z kontekstem
    print("  M4: Dodaję intentPatterns dla 'zrób' z kontekstem...")

    # build - zrób z kontekstem UI/feature
    add_intent_patterns(rules, 'skills', 'build', [
        "(zrób|zrob|stwórz|stworz).*(GUI|interfejs|UI|okno|formularz|widok|ekran)",
        "(zrób|zrob|stwórz|stworz).*(funkcjonalność|funkcjonalnosc|feature|ficzer)",
        "(zrób|zrob|stwórz|stworz).*(endpoint|API|serwis|service)",
    ])

    # compound-learnings - zrób z kontekstem skill/rule
    add_intent_patterns(rules, 'skills', 'compound-learnings', [
        "(zrób|zrob|stwórz|stworz).*(skill|umiejętność|umiejetnosc|regułę|regule)",
        "(zrób|zrob).*(z tego|z tych).*(skill|regułę|regule|agent)",
    ])

    # release - zrób z kontekstem release/deploy
    add_intent_patterns(rules, 'skills', 'release', [
        "(zrób|zrob|przygotuj).*(release|wydanie|deploy|wdrożenie|wdrozenie)",
        "(zrób|zrob).*(wersj|version)",
    ])

def main():
    input_path = Path("D:/Projekty DELL KG/KFG-Addons/addons/ccv3-polish-translation/files/skills/skill-rules.json")
    output_path = Path("D:/Projekty DELL KG/KFG-Addons/addons/ccv3-polish-translation/files/skills/skill-rules-v6.json")

    print("CCv3 Polish Translation - V6 Fixes")
    print("=" * 50)

    print("\nŁaduję V5...")
    rules = load_rules(input_path)

    print("\nNaprawiam HIGH issues...")
    fix_high_issues(rules)

    print("\nNaprawiam MEDIUM issues...")
    fix_medium_issues(rules)

    print(f"\nZapisuję V6 do: {output_path}")
    save_rules(rules, output_path)

    # Nadpisz główny plik
    main_path = input_path
    print(f"Nadpisuję główny plik: {main_path}")
    save_rules(rules, main_path)

    print("\n" + "=" * 50)
    print("V6 GOTOWE!")
    print("Pliki:")
    print(f"  - {output_path}")
    print(f"  - {main_path}")

if __name__ == "__main__":
    main()
