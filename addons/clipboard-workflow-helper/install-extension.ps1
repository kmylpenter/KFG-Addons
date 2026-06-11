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
        # M35: @(...) wymusza tablice — bez tego 1 wynik = obiekt, 0 wynikow = $null,
        # a .Count i serializacja sypia sie / zapisuja zly ksztalt.
        $extJson = @(Get-Content -LiteralPath $extensionsJsonPath -Raw | ConvertFrom-Json)
        $originalCount = $extJson.Count

        $extJson = @($extJson | Where-Object {
            $_.identifier.id -notmatch "clipboard-workflow-helper"
        })

        $removedCount = $originalCount - $extJson.Count
        if ($removedCount -gt 0) {
            # backup przed zapisem cudzego configu
            Copy-Item -LiteralPath $extensionsJsonPath -Destination "$extensionsJsonPath.bak-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')" -Force
            if ($extJson.Count -eq 0) {
                $json = "[]"
            } else {
                $json = ConvertTo-Json -InputObject $extJson -Depth 10
                # PS5.1: ConvertTo-Json na 1-elem tablicy daje OBIEKT — wymus nawiasy tablicy
                if ($extJson.Count -eq 1) { $json = "[$json]" }
            }
            # zapis bez BOM (Set-Content -Encoding UTF8 dodaje BOM -> psuje JSON.parse)
            [System.IO.File]::WriteAllText($extensionsJsonPath, $json, [System.Text.UTF8Encoding]::new($false))
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

Write-Info "Kopiowanie do $targetDir"
# M10: jesli target przetrwal czyszczenie (lock/AV), Copy-Item -Recurse ZAGNIEZDZILBY
# zrodlo jako podfolder (rozbita extension). Oprozni target przed kopia.
if (Test-Path -LiteralPath $targetDir) {
    try {
        Remove-Item -LiteralPath $targetDir -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warn "Nie mozna oproznic $targetDir ($_) — przerywam, nie zagniezdzam kopii"
        exit 1
    }
}
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
# M38: -Exclude na sciezce KATALOGOWEJ nie filtruje dzieci w WinPS5.1 — kopiuj ZAWARTOSC ('\*'),
# wtedy -Exclude dziala na elementach top-level.
Copy-Item -Path (Join-Path $extensionSourceDir '*') -Destination $targetDir -Recurse -Force -Exclude "ClipboardListener.exe" -ErrorAction Stop
# M38 backstop: gdyby exe sie przeslizgnal mimo -Exclude, usun po kopii
$strayExe = Join-Path $targetDir "ClipboardListener.exe"
if (Test-Path -LiteralPath $strayExe) { Remove-Item -LiteralPath $strayExe -Force -ErrorAction SilentlyContinue }
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
