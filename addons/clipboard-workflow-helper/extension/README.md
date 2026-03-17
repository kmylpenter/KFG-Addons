# Clipboard Workflow Helper (for Claude Code)

VSCode extension do automatycznego tworzenia backupów plików na Timeline - szczególnie przydatne przy pracy z Claude Code.

## Problem który rozwiązuje

Gdy Claude Code edytuje pliki przez Edit/Write tool:
- VSCode nie widzi tego jako "save" (brak `onDidSaveTextDocument`)
- Brak automatycznych wpisów na Timeline
- Ryzyko utraty zmian bez możliwości powrotu

## Funkcje

### 1. Copy and Unselect (Ctrl+C)
- Kopiuje zaznaczony tekst do schowka
- Automatycznie odznacza selekcję (cursor na końcu)

### 2. Copy + Timeline Entry (Ctrl+A → Ctrl+C)
- Sekwencja: Ctrl+A (zaznacz wszystko), potem Ctrl+C w ciągu 2s
- Kopiuje cały plik do schowka
- Tworzy wpis na Timeline z:
  - Tytułem z komentarza `// ==Save: Tytuł==` (jeśli istnieje)
  - Stats zmian `+X/-Y chars`

### 3. Auto-Backup (automatyczny)
- **Trigger 1:** `onDidSaveTextDocument` - każdy ręczny save (Ctrl+S)
- **Trigger 2:** `FileSystemWatcher.onDidChange` - zewnętrzne zmiany (Claude Code!)
- **Debounce:** max 1 backup na 30 sekund per plik
- **Tytuł:** z komentarza `// ==Save: ...==` lub "Auto-save"

## Architektura

```
src/
├── extension.ts              # Entry point, rejestracja komend i listenerów
├── commands/
│   ├── copyAndUnselect.ts    # Ctrl+C - kopiuj + odznacz
│   └── copyAndCreateTimeline.ts  # Ctrl+A+C - kopiuj + timeline
└── utils/
    ├── autoBackupManager.ts  # Manager auto-backup z debounce
    ├── changeTracker.ts      # Śledzenie zmian (+/- chars)
    ├── timelineManager.ts    # Tworzenie wpisów Timeline (VSCode History)
    ├── timelineManifest.ts   # Manifest dla merge script
    ├── titleParser.ts        # Parsowanie tytułu z komentarza
    ├── titleCache.ts         # Cache tytułów (recovery)
    ├── entriesJsonUpdater.ts # Update entries.json z source field
    └── timelineMerge.ts      # Node.js script uruchamiany przy deactivate
```

## Kluczowe klasy

### AutoBackupManager (`autoBackupManager.ts`)
```typescript
// Debounce - max 1 backup / 30s per file
static async handleSave(document: TextDocument): Promise<void>

// Reset timer po ręcznym backup (Ctrl+A+C)
static resetTimer(uri: string): void
```

### TimelineManager (`timelineManager.ts`)
```typescript
// Dodaj wpis na Timeline (VSCode Local History)
static async addTimelineEntry(document: TextDocument, label: string): Promise<boolean>
```

### TitleParser (`titleParser.ts`)
```typescript
// Parsuj tytuł z pierwszych 20 linii pliku
// Szuka wzorca: // ==Save: Tytuł==
static parseTitle(document: TextDocument): { title: string | null, lineNumber: number | null }
```

## Triggery i Flow

### Ręczny save (Ctrl+S)
```
User: Ctrl+S
  → VSCode: document.save()
  → Event: onDidSaveTextDocument
  → AutoBackupManager.handleSave()
  → (debounce check)
  → TimelineManager.addTimelineEntry()
```

### Claude Code edycja
```
Claude: Edit/Write tool
  → Filesystem: plik zmieniony
  → Event: FileSystemWatcher.onDidChange
  → (delay 200ms - bug VSCode #72831)
  → AutoBackupManager.handleSave()
  → (debounce check)
  → TimelineManager.addTimelineEntry()
```

### Ctrl+A → Ctrl+C
```
User: Ctrl+A
  → selectAllWithTimeout: zaznacz + ustaw flag awaitingCtrlC
  → (timeout 2s)
User: Ctrl+C (w ciągu 2s)
  → copyAndCreateTimeline()
  → copy to clipboard
  → TimelineManager.addTimelineEntry()
  → AutoBackupManager.resetTimer() // zapobiega duplikatom
```

## Format tytułu w pliku

Extension parsuje tytuł z komentarza w pierwszych 20 liniach:

```javascript
// ==Save: Dodano walidację formularza==
```

```python
# ==Save: Fix bug w funkcji calculate==
```

```sql
-- ==Save: Nowa tabela users==
```

```html
<!-- ==Save: Redesign header== -->
```

## Konfiguracja (package.json)

```json
{
  "clipboardHelper.ctrlACtrlCTimeout": {
    "type": "number",
    "default": 2000,
    "description": "Timeout (ms) na Ctrl+C po Ctrl+A"
  },
  "clipboardHelper.backgroundTaskIntervalMinutes": {
    "type": "number",
    "default": 10,
    "description": "Interval background task (recovery titles)"
  }
}
```

## Pliki konfiguracyjne extension

| Plik | Lokalizacja | Opis |
|------|-------------|------|
| `timeline-config.json` | extensionPath | Ścieżki History per komputer |
| `timeline-cache.json` | extensionPath | Cache ostatniego folderu History |
| `.timeline-manifest.json` | extensionPath | Pending updates dla merge script |
| `title-cache.json` | globalStoragePath | Cache tytułów (AppData) |

## VSCode History Location

Windows: `%APPDATA%\Code\User\History\`

Każdy plik ma swój folder (hash), np:
```
History/
├── 40eb624d/           # hash dla pliku X
│   ├── entries.json    # metadane wpisów
│   ├── aBcD.ts         # backup 1
│   └── xYzW.ts         # backup 2
└── 7f3a9b12/           # hash dla pliku Y
    └── ...
```

## Debug

1. View → Output → "Clipboard Helper"
2. Logi pokazują:
   - `[AutoBackup]` - auto-backup events
   - `[FileWatcher]` - zewnętrzne zmiany
   - `[Timeline]` - tworzenie wpisów

## Kompilacja

```bash
cd .vscode/extensions/clipboard-workflow-helper
npm install
npm run compile
```

## Znane problemy

1. **FileSystemWatcher stale content** ([#72831](https://github.com/microsoft/vscode/issues/72831))
   - Rozwiązanie: delay 200ms przed odczytem pliku

2. **entries.json locked by VSCode**
   - Rozwiązanie: retry logic + merge script przy deactivate

## TODO / Pomysły na rozwój

- [ ] Konfigurowalny debounce time (obecnie hardcoded 30s)
- [ ] Filtrowanie rozszerzeń plików dla auto-backup
- [ ] Exclude patterns (np. `*.log`, `*.tmp`)
- [ ] Status bar indicator gdy auto-backup jest aktywny
- [ ] Notification gdy backup się nie powiódł

## Changelog

### v1.1.0 (2025-12-17) - Fix Claude Code compatibility
**Problem:** Auto-backup wywoływał `files.save` co modyfikowało plik podczas edycji przez Claude Code, powodując błędy "File has been modified".

**Rozwiązanie:**
- Nowy parametr `skipSave` w `addTimelineEntry()` - dla auto-backup nie wywołuje `files.save`
- `getOrCreateHistoryFolder()` - tworzy folder History samodzielnie z **DOKŁADNYM algorytmem hash VSCode**
- `addEntryToEntriesJson()` - dodaje entry bezpośrednio do entries.json
- `findHistoryFolderByResource()` - szuka istniejącego folderu History po URI
- **Cooldown 2s** - backup dopiero po 2s bez kolejnych zmian (zapobiega kolizji z "burst" edycjami Claude)

**Hash algorithm VSCode** (z `vs/base/common/hash.ts`):
```typescript
// ((initialHashVal << 5) - initialHashVal) + val
// Start: numberHash(149417, 0)
```
Zweryfikowany: 8/8 hashów identycznych z VSCode.

**Dodatkowe poprawki:**
- timelineMerge.ts - naprawiony filtr `.dg` → skanuje WSZYSTKIE rozszerzenia plików

### v1.0.0
- Ctrl+C copy + unselect
- Ctrl+A+C copy + timeline
- Auto-backup na save (onDidSaveTextDocument)
- Auto-backup na zewnętrzne zmiany (FileSystemWatcher)
- Parsowanie tytułu z komentarza
- Debounce 30s
