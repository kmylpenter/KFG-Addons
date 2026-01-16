# Tworzenie Dodatkow KFG

Instrukcja tworzenia nowych dodatkow dla KFG-Addons.

## Struktura Dodatku

```
addons/
└── nazwa-dodatku/
    ├── addon.json          # WYMAGANE - metadata
    ├── install.ps1         # OPCJONALNE - custom instalator
    └── files/              # WYMAGANE - pliki do skopiowania
        ├── skills/         # Skills dla Claude Code
        │   └── nazwa/
        │       └── SKILL.md
        ├── templates/      # Szablony i skrypty
        │   └── scripts/
        │       └── *.py
        ├── hooks/          # Hooki Claude Code
        │   └── *.ps1
        └── [inne]/         # Dowolna struktura
```

## addon.json - Specyfikacja

```json
{
  "name": "nazwa-dodatku",
  "displayName": "Czytelna Nazwa",
  "description": "Krotki opis co robi dodatek",
  "version": "1.0.0",
  "author": "twoj-username",

  "dependencies": {
    "python": {
      "required": true,
      "minVersion": "3.8",
      "packages": ["requests", "pillow"]
    },
    "node": {
      "required": false,
      "minVersion": "18",
      "packages": ["puppeteer"]
    }
  },

  "targets": {
    "files/skills/nazwa/": "~/.claude/skills/nazwa/",
    "files/templates/scripts/": "~/.templates/scripts/",
    "files/hooks/": "~/.claude/hooks/"
  },

  "postInstall": "echo 'Gotowe!'",
  "notes": "Dodatkowe uwagi dla uzytkownika"
}
```

### Pola wymagane

| Pole | Typ | Opis |
|------|-----|------|
| `name` | string | Unikalna nazwa (lowercase, bez spacji) |
| `displayName` | string | Nazwa wyswietlana |
| `description` | string | Krotki opis |
| `version` | string | Wersja semver (1.0.0) |
| `targets` | object | Mapowanie zrodlo -> cel |

### Pola opcjonalne

| Pole | Typ | Opis |
|------|-----|------|
| `author` | string | Autor dodatku |
| `dependencies` | object | Zaleznosci systemowe |
| `postInstall` | string | Komenda po instalacji |
| `notes` | string | Uwagi dla uzytkownika |

## Zaleznosci

### Obslugiwane typy

| Typ | Sprawdzanie | Auto-instalacja |
|-----|-------------|-----------------|
| `python` | `python --version` | winget + pip |
| `node` | `node --version` | winget + npm |
| inne | `Get-Command` | pytanie uzytkownika |

### Pakiety Python

```json
"dependencies": {
  "python": {
    "required": true,
    "minVersion": "3.8",
    "packages": ["requests", "beautifulsoup4"]
  }
}
```

Instalator automatycznie zainstaluje pakiety przez `pip install`.

### Pakiety Node

```json
"dependencies": {
  "node": {
    "required": true,
    "packages": ["puppeteer"]
  }
}
```

## Targets - Mapowanie Plikow

Format: `"sciezka/w/repo/": "sciezka/docelowa/"`

### Specjalne sciezki

| Symbol | Rozwiniecie (Windows) |
|--------|----------------------|
| `~/` | `C:\Users\USERNAME\` |
| `~/.claude/` | `C:\Users\USERNAME\.claude\` |
| `~/.templates/` | `C:\Users\USERNAME\.templates\` |

### Wzorce targets (WAZNE!)

Installer v2.2+ obsluguje trzy wzorce:

#### 1. Katalog do katalogu (zalecane)

```json
"files/skills/moj-skill/": "~/.claude/skills/moj-skill/"
```
Kopiuje ZAWARTOSC `moj-skill/` do docelowego `moj-skill/`.

#### 2. Katalog do rodzica

```json
"files/.claude/skills/np/": "~/.claude/skills/"
```
Kopiuje folder `np/` DO katalogu `skills/`, wynik: `~/.claude/skills/np/`

#### 3. Pojedynczy plik

```json
"files/.claude/statusline-wrapper.ps1": "~/.claude/"
```
Kopiuje plik do katalogu, wynik: `~/.claude/statusline-wrapper.ps1`

### Przyklady

```json
"targets": {
  "files/skills/moj-skill/": "~/.claude/skills/moj-skill/",
  "files/scripts/": "~/.templates/scripts/",
  "files/hooks/": "~/.claude/hooks/",
  "files/.claude/moj-skrypt.ps1": "~/.claude/"
}
```

### WAZNE - unikaj bledow

| Wzorzec | Status | Uwagi |
|---------|--------|-------|
| `"files/skills/x/": "~/.claude/skills/x/"` | OK | Katalog do katalogu (explicit) |
| `"files/skills/x/": "~/.claude/skills/"` | OK | Katalog do rodzica (v2.2+) |
| `"files/skrypt.ps1": "~/.claude/"` | OK | Plik do katalogu (v2.1+) |
| `"files/skills/": "~/.claude/skills/"` | UWAGA | Kopiuje ZAWARTOSC, nie folder |

**WAZNE:** Koncz sciezki folderow na `/`

## Przyklad: Prosty Skill

### Struktura

```
addons/
└── hello-world/
    ├── addon.json
    └── files/
        └── skills/
            └── hello/
                └── SKILL.md
```

### addon.json

```json
{
  "name": "hello-world",
  "displayName": "Hello World Skill",
  "description": "Prosty przykladowy skill",
  "version": "1.0.0",
  "dependencies": {},
  "targets": {
    "files/skills/hello/": "~/.claude/skills/hello/"
  }
}
```

### SKILL.md

```markdown
---
description: Przykladowy skill hello world
---

# Hello World

Gdy uzytkownik uzyje /hello, odpowiedz "Hello World!"
```

## Przyklad: Skill z Python

### Struktura

```
addons/
└── screenshot-tool/
    ├── addon.json
    └── files/
        ├── skills/
        │   └── screenshot/
        │       └── SKILL.md
        └── templates/
            └── scripts/
                └── capture_screenshot.py
```

### addon.json

```json
{
  "name": "screenshot-tool",
  "displayName": "Screenshot Tool",
  "description": "Przechwytywanie screenshotow stron web",
  "version": "1.0.0",
  "dependencies": {
    "python": {
      "required": true,
      "minVersion": "3.8",
      "packages": ["pillow", "selenium"]
    }
  },
  "targets": {
    "files/skills/screenshot/": "~/.claude/skills/screenshot/",
    "files/templates/scripts/": "~/.templates/scripts/"
  },
  "notes": "Wymaga Chrome/Chromium zainstalowanego"
}
```

## Testowanie Dodatku

### 1. Lokalna instalacja

```powershell
cd KFG-Addons
.\install-addons.ps1 -Addon nazwa-dodatku
```

### 2. Weryfikacja plikow

```powershell
# Sprawdz czy pliki zostaly skopiowane
dir ~/.claude/skills/nazwa-dodatku/
dir ~/.templates/scripts/
```

### 3. Test w Claude Code

```
> /nazwa-dodatku
```

## Checklist przed PR

- [ ] `addon.json` poprawny JSON
- [ ] `name` unikalne (sprawdz istniejace)
- [ ] `targets` koncza sie na `/` dla folderow
- [ ] Wszystkie pliki w `files/` istnieja
- [ ] Zaleznosci poprawnie zdefiniowane
- [ ] Przetestowane lokalnie
- [ ] SKILL.md ma frontmatter `---description:---`

## FAQ

### Jak dodac nowy dodatek?

1. Utworz folder w `addons/`
2. Dodaj `addon.json`
3. Dodaj pliki w `files/`
4. Przetestuj: `.\install-addons.ps1 -Addon twoj-dodatek`
5. Commit & PR

### Jak zaktualizowac istniejacy?

1. Zmien `version` w `addon.json`
2. Zaktualizuj pliki w `files/`
3. Commit & PR

### Jak usunac zainstalowany dodatek?

Recznie usun pliki z lokalizacji docelowych:
```powershell
Remove-Item -Recurse ~/.claude/skills/nazwa-dodatku/
```

### Moj dodatek wymaga konfiguracji

Dodaj instrukcje w `notes` lub utworz `files/docs/SETUP.md`.
