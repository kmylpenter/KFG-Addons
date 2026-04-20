# Clipboard Workflow Helper - VS Code Extension Installer
# Kopiuje rozszerzenie bezposrednio do ~/.vscode/extensions/

$ErrorActionPreference = "Stop"

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }
function Write-Header { param([string]$Msg) Write-Host "`n  === $Msg ===" -ForegroundColor Yellow }

$addonDir = $env:ADDON_DIR
if (-not $addonDir) {
    $addonDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$extensionSourceDir = Join-Path $addonDir "extension"

# ============================================================
# 1. CZYSZCZENIE STARYCH WERSJI
# ============================================================
Write-Header "Czyszczenie starych wersji"

$vsCodeExtDir = "$env:USERPROFILE\.vscode\extensions"
$extensionsJsonPath = Join-Path $vsCodeExtDir "extensions.json"

# Usun stare foldery
$oldPatterns = @(
    "local.clipboard-workflow-helper-*",
    "clipboard-workflow-helper-*"
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

# Wyczysc extensions.json cache
if (Test-Path $extensionsJsonPath) {
    try {
        $extJson = Get-Content $extensionsJsonPath -Raw | ConvertFrom-Json
        $originalCount = $extJson.Count

        $extJson = $extJson | Where-Object {
            $_.identifier.id -notmatch "clipboard-workflow-helper"
        }

        $removedCount = $originalCount - $extJson.Count
        if ($removedCount -gt 0) {
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
# 2. KOPIOWANIE EXTENSION
# ============================================================
Write-Header "Instalacja Extension"

$targetDir = Join-Path $vsCodeExtDir "local.clipboard-workflow-helper-1.2.0"

# v1.2.1: Defensywne usuniecie legacy ClipboardListener.exe z source i target
# (Bitdefender flaguje go jako Trojan - pozostalosc po v1.1.0)
$legacyExePaths = @(
    (Join-Path $extensionSourceDir "ClipboardListener.exe"),
    (Join-Path $targetDir "ClipboardListener.exe")
)
foreach ($legacy in $legacyExePaths) {
    if (Test-Path $legacy) {
        try {
            Remove-Item -Path $legacy -Force -ErrorAction Stop
            Write-Info "Usunieto legacy: $legacy"
        } catch {
            Write-Warn "Nie mozna usunac (Bitdefender lock?): $legacy - zostanie pominiety"
        }
    }
}

# Kopiuj calosc (wyklucz legacy ClipboardListener.exe gdyby przetrwal)
Write-Info "Kopiowanie do $targetDir"
Copy-Item -Path $extensionSourceDir -Destination $targetDir -Recurse -Force -Exclude "ClipboardListener.exe" -ErrorAction Continue

Write-OK "Extension skopiowana"

# ============================================================
# PODSUMOWANIE
# ============================================================
Write-Host ""
Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "  |    Clipboard Workflow Helper v1.2 - Zainstalowany         |" -ForegroundColor Cyan
Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "    Funkcje:" -ForegroundColor White
Write-Host "      - Ctrl+C: kopiuj + odznacz selekcje" -ForegroundColor Gray
Write-Host "      - Ctrl+A -> Ctrl+C: kopiuj + timeline entry" -ForegroundColor Gray
Write-Host "      - Auto-backup plikow (Claude Code compatible)" -ForegroundColor Gray
Write-Host "      - Ctrl+Shift+V: wklej screenshot do terminala" -ForegroundColor Gray
Write-Host ""

$vsCodeRunning = Get-Process -Name "Code" -ErrorAction SilentlyContinue
if ($vsCodeRunning) {
    Write-Host "    WAZNE: Uruchom ponownie VS Code!" -ForegroundColor Yellow
}

Write-Host ""
