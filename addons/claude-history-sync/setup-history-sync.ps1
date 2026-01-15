# ============================================================
# Claude History Sync Setup
# ============================================================
# Konfiguruje synchronizacje historii Claude miedzy urzadzeniami
#
# Bezpieczna kolejnosc:
# 1. Klonuje git repo do ~/.claude-history
# 2. Przenosi istniejace konwersacje do sklonowanego repo
# 3. Tworzy Junction z ~/.claude/projects -> ~/.claude-history
# ============================================================

param(
    [string]$HistoryRepo = "https://github.com/kmylpenter/claude-history.git",
    [string]$HistoryDir = "$env:USERPROFILE\.claude-history",
    [string]$ProjectsLink = "$env:USERPROFILE\.claude\projects"
)

$ErrorActionPreference = "Stop"

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Err { param([string]$Msg) Write-Host "    [X] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }

Write-Host ""
Write-Host "  Claude History Sync Setup" -ForegroundColor Yellow
Write-Host "  ============================================================" -ForegroundColor DarkGray

# ============================================================
# KROK 1: Clone lub pull history repo
# ============================================================

Write-Info "KROK 1: Sprawdzam repozytorium historii..."

if (Test-Path $HistoryDir) {
    if (Test-Path (Join-Path $HistoryDir ".git")) {
        Write-OK "Repo juz istnieje - wykonuje git pull"
        Push-Location $HistoryDir
        try {
            git pull --quiet 2>&1 | Out-Null
            Write-OK "Git pull OK"
        } catch {
            Write-Warn "Git pull failed: $_"
        }
        Pop-Location
    } else {
        Write-Warn "$HistoryDir istnieje ale to nie git repo!"
        $backup = "${HistoryDir}_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-Info "Tworze backup: $backup"
        Move-Item $HistoryDir $backup

        Write-Info "Klonuje $HistoryRepo..."
        git clone $HistoryRepo $HistoryDir
        Write-OK "Sklonowano!"
    }
} else {
    Write-Info "Klonuje $HistoryRepo do $HistoryDir..."
    git clone $HistoryRepo $HistoryDir
    Write-OK "Sklonowano!"
}

# ============================================================
# KROK 2: Przenies istniejace konwersacje do repo
# ============================================================

Write-Info "KROK 2: Sprawdzam istniejace konwersacje..."

$linkItem = Get-Item $ProjectsLink -ErrorAction SilentlyContinue

if ($linkItem) {
    if ($linkItem.LinkType -eq "Junction") {
        $target = $linkItem.Target
        if ($target -eq $HistoryDir -or $target -contains $HistoryDir) {
            Write-OK "Junction juz prawidlowy - pomijam migracje"
        } else {
            Write-Warn "Junction wskazuje na: $target (oczekiwano: $HistoryDir)"
            Write-Info "Usuwam stary junction..."
            Remove-Item $ProjectsLink -Force
        }
    } elseif ($linkItem.PSIsContainer) {
        # To zwykly folder z konwersacjami - MIGRACJA!
        Write-Warn "$ProjectsLink to folder z konwersacjami"

        # Policz pliki do migracji
        $files = Get-ChildItem $ProjectsLink -File -ErrorAction SilentlyContinue
        $folders = Get-ChildItem $ProjectsLink -Directory -ErrorAction SilentlyContinue
        $totalItems = ($files.Count + $folders.Count)

        if ($totalItems -gt 0) {
            Write-Info "Znaleziono $totalItems elementow do migracji"
            Write-Info "Kopiuje konwersacje do $HistoryDir..."

            # Kopiuj wszystko do repo (nie nadpisuj istniejacych)
            $copied = 0
            $skipped = 0

            foreach ($item in (Get-ChildItem $ProjectsLink)) {
                $destPath = Join-Path $HistoryDir $item.Name
                if (-not (Test-Path $destPath)) {
                    Copy-Item $item.FullName $destPath -Recurse -Force
                    $copied++
                } else {
                    $skipped++
                }
            }

            Write-OK "Skopiowano: $copied, pominieto (juz istnieja): $skipped"
        }

        # Tworz backup i usun folder
        $backup = "${ProjectsLink}_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Write-Info "Backup oryginalnego folderu: $backup"
        Move-Item $ProjectsLink $backup
        Write-OK "Konwersacje bezpiecznie zmigrowane!"
    } else {
        Write-Err "$ProjectsLink to plik - nie moge kontynuowac"
        exit 1
    }
}

# ============================================================
# KROK 3: Utworz Junction
# ============================================================

Write-Info "KROK 3: Tworzenie junction..."

# Upewnij sie ze .claude folder istnieje
$claudeDir = Split-Path $ProjectsLink -Parent
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    Write-OK "Utworzono $claudeDir"
}

# Sprawdz czy junction juz istnieje i jest prawidlowy
$existingLink = Get-Item $ProjectsLink -ErrorAction SilentlyContinue
if ($existingLink -and $existingLink.LinkType -eq "Junction") {
    $target = $existingLink.Target
    if ($target -eq $HistoryDir -or $target -contains $HistoryDir) {
        Write-OK "Junction juz prawidlowy!"
    } else {
        Remove-Item $ProjectsLink -Force
        cmd /c mklink /J "$ProjectsLink" "$HistoryDir" | Out-Null
        Write-OK "Junction naprawiony!"
    }
} elseif (-not $existingLink) {
    cmd /c mklink /J "$ProjectsLink" "$HistoryDir" | Out-Null
    Write-OK "Junction utworzony!"
} else {
    Write-Err "Nieoczekiwany stan - $ProjectsLink nadal istnieje"
    exit 1
}

# ============================================================
# KROK 4: Verify
# ============================================================

Write-Info "KROK 4: Weryfikacja..."

$verify = Get-Item $ProjectsLink -ErrorAction SilentlyContinue
if ($verify -and $verify.LinkType -eq "Junction") {
    Write-OK "Weryfikacja OK!"
} else {
    Write-Err "Weryfikacja FAILED - junction nie dziala"
    exit 1
}

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "  Claude History Sync skonfigurowany!" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "    Historia: $HistoryDir" -ForegroundColor Cyan
Write-Host "    Link:     $ProjectsLink -> $HistoryDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Aby zsynchronizowac na innym urzadzeniu:" -ForegroundColor Gray
Write-Host "    cd ~/.claude-history && git pull" -ForegroundColor Gray
Write-Host ""
