# Dynamic Terminal Saver - VS Code Extension Installer
# Czysci stare wersje i instaluje nowa

$ErrorActionPreference = "Stop"

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }
function Write-Header { param([string]$Msg) Write-Host "`n  === $Msg ===" -ForegroundColor Yellow }

$addonDir = $env:ADDON_DIR
if (-not $addonDir) {
    $addonDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$extensionDir = Join-Path $addonDir "extension"

# ============================================================
# 1. CZYSZCZENIE STARYCH WERSJI
# ============================================================
Write-Header "Czyszczenie starych wersji"

$vsCodeExtDir = "$env:USERPROFILE\.vscode\extensions"
$extensionsJsonPath = Join-Path $vsCodeExtDir "extensions.json"

# 1a. Usun stare foldery
$oldPatterns = @(
    "vscode-local.dynamic-terminal-saver-*",
    "dynamic-terminal-saver-*"
)

$cleaned = 0
foreach ($pattern in $oldPatterns) {
    $oldDirs = Get-ChildItem -Path $vsCodeExtDir -Directory -Filter $pattern -ErrorAction SilentlyContinue
    foreach ($dir in $oldDirs) {
        try {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
            Write-OK "Usunieto folder: $($dir.Name)"
            $cleaned++
        } catch {
            Write-Warn "Nie mozna usunac $($dir.Name): $_"
        }
    }
}

# 1b. Wyczysc extensions.json (VS Code cache)
if (Test-Path $extensionsJsonPath) {
    try {
        $extJson = Get-Content $extensionsJsonPath -Raw | ConvertFrom-Json
        $originalCount = $extJson.Count

        # Filtruj - usun wpisy dla dynamic-terminal-saver
        $extJson = $extJson | Where-Object {
            $_.identifier.id -notmatch "dynamic-terminal-saver"
        }

        $removedCount = $originalCount - $extJson.Count
        if ($removedCount -gt 0) {
            # Zapisz zaktualizowany JSON
            $extJson | ConvertTo-Json -Depth 10 | Set-Content $extensionsJsonPath -Encoding UTF8
            Write-OK "Usunieto $removedCount wpisow z extensions.json"
            $cleaned += $removedCount
        }
    } catch {
        Write-Warn "Nie mozna zaktualizowac extensions.json: $_"
    }
}

if ($cleaned -eq 0) {
    Write-Info "Brak starych wersji do usuniecia"
} else {
    Write-OK "Wyczyszczono $cleaned elementow"
}

# ============================================================
# 2. INSTALACJA DEPENDENCIES
# ============================================================
Write-Header "Instalacja dependencies"

Push-Location $extensionDir
try {
    if (-not (Test-Path "node_modules")) {
        Write-Info "npm install..."
        npm install --silent 2>$null
        Write-OK "Dependencies zainstalowane"
    } else {
        Write-Info "Dependencies juz zainstalowane"
    }
} finally {
    Pop-Location
}

# ============================================================
# 3. KOMPILACJA TYPESCRIPT
# ============================================================
Write-Header "Kompilacja TypeScript"

Push-Location $extensionDir
try {
    Write-Info "tsc -p ./"
    npm run compile --silent 2>$null

    if (Test-Path "out\extension.js") {
        Write-OK "Kompilacja zakonczona"
    } else {
        throw "Brak pliku out/extension.js po kompilacji"
    }
} finally {
    Pop-Location
}

# ============================================================
# 4. PAKOWANIE VSIX
# ============================================================
Write-Header "Pakowanie VSIX"

Push-Location $extensionDir
try {
    # Usun stary VSIX
    Get-ChildItem -Filter "*.vsix" | Remove-Item -Force -ErrorAction SilentlyContinue

    Write-Info "vsce package..."
    $result = npx vsce package --allow-missing-repository 2>&1

    $vsixFile = Get-ChildItem -Filter "*.vsix" | Select-Object -First 1
    if ($vsixFile) {
        Write-OK "Utworzono: $($vsixFile.Name)"
    } else {
        throw "Nie utworzono pliku VSIX"
    }
} finally {
    Pop-Location
}

# ============================================================
# 5. INSTALACJA EXTENSION
# ============================================================
Write-Header "Instalacja Extension"

$vsixPath = Join-Path $extensionDir $vsixFile.Name

# Sprawdz czy VS Code jest uruchomiony
$vsCodeRunning = Get-Process -Name "Code" -ErrorAction SilentlyContinue

if ($vsCodeRunning) {
    Write-Warn "VS Code jest uruchomiony"
    Write-Info "Extension zostanie zainstalowana, ale wymaga restartu VS Code"
}

try {
    Write-Info "code --install-extension $($vsixFile.Name) --force"
    $installResult = & code --install-extension $vsixPath --force 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-OK "Extension zainstalowana"
    } else {
        # Moze byc blad "Please restart VS Code" - to OK
        if ($installResult -match "restart") {
            Write-Warn "VS Code wymaga restartu przed ponowna instalacja"
            Write-Info "Zamknij VS Code, uruchom ponownie i extension bedzie aktywna"
        } else {
            throw "Blad instalacji: $installResult"
        }
    }
} catch {
    Write-Warn "Blad: $_"
    Write-Info "Sprobuj recznie: code --install-extension `"$vsixPath`" --force"
}

# ============================================================
# PODSUMOWANIE
# ============================================================
Write-Host ""
Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "  |       Dynamic Terminal Saver v1.1 - Zainstalowany         |" -ForegroundColor Cyan
Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "    Funkcje:" -ForegroundColor White
Write-Host "      - Zapisywanie/przywracanie terminali z kolorami i ikonkami" -ForegroundColor Gray
Write-Host "      - Layout States (dynamiczna wysokosc panelu)" -ForegroundColor Gray
Write-Host "      - Auto-restore przy starcie VS Code" -ForegroundColor Gray
Write-Host "      - Logi w .vscode/dynamic-terminal-saver.log" -ForegroundColor Gray
Write-Host ""
Write-Host "    Skroty klawiszowe:" -ForegroundColor White
Write-Host "      Ctrl+Alt+S  - Zapisz stan terminali" -ForegroundColor Gray
Write-Host "      Ctrl+Alt+L  - Toggle Layout Lock" -ForegroundColor Gray
Write-Host ""
Write-Host "    Wymaga: Claude Code for VS Code (anthropic.claude-code)" -ForegroundColor DarkGray
Write-Host ""

if ($vsCodeRunning) {
    Write-Host "    WAZNE: Uruchom ponownie VS Code aby aktywowac extension!" -ForegroundColor Yellow
}

Write-Host ""
