# Install Safe Permissions Addon v3
# YOLO Mode Protection - 4-warstwowa ochrona

param([switch]$Force)

$ErrorActionPreference = "Stop"
$claudeDir = "$env:USERPROFILE\.claude"
$hooksDir = "$claudeDir\hooks"
$srcDir = "$hooksDir\src"
$distDir = "$hooksDir\dist"
$settingsFile = "$claudeDir\settings.json"

Write-Host "=== Safe Permissions v3 (YOLO Protection) ===" -ForegroundColor Cyan
Write-Host "4 warstwy ochrony dla --dangerously-skip-permissions" -ForegroundColor Gray

# 1. Sprawdz/zainstaluj trash-cli
Write-Host "`n[1/6] trash-cli..." -ForegroundColor Yellow
$trashPath = Get-Command trash -ErrorAction SilentlyContinue
if (-not $trashPath) {
    Write-Host "  Instaluje trash-cli..." -ForegroundColor Yellow
    npm install -g trash-cli 2>&1 | Out-Null
    $trashPath = Get-Command trash -ErrorAction SilentlyContinue
    if (-not $trashPath) {
        Write-Host "  BLAD: npm install -g trash-cli nie powiodlo sie" -ForegroundColor Red
        Write-Host "  Uruchom recznie i sprobuj ponownie" -ForegroundColor Yellow
        exit 1
    }
}
Write-Host "  OK: $($trashPath.Source)" -ForegroundColor Green

# 2. Sprawdz/zainstaluj esbuild
Write-Host "`n[2/6] esbuild..." -ForegroundColor Yellow
$esbuildPath = Get-Command esbuild -ErrorAction SilentlyContinue
if (-not $esbuildPath) {
    Write-Host "  Instaluje esbuild..." -ForegroundColor Yellow
    npm install -g esbuild 2>&1 | Out-Null
    $esbuildPath = Get-Command esbuild -ErrorAction SilentlyContinue
    if (-not $esbuildPath) {
        Write-Host "  BLAD: npm install -g esbuild nie powiodlo sie" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  OK: $($esbuildPath.Source)" -ForegroundColor Green

# 3. Kompiluj hook
Write-Host "`n[3/6] Kompilacja hooka..." -ForegroundColor Yellow
$hookSrc = "$srcDir\safe-permissions.ts"
$hookDist = "$distDir\safe-permissions.mjs"

if (-not (Test-Path $hookSrc)) {
    Write-Host "  BLAD: Brak pliku zrodlowego $hookSrc" -ForegroundColor Red
    exit 1
}

# Utworz dist folder
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
}

# Kompiluj z esbuild
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
esbuild $hookSrc --bundle --platform=node --format=esm --outfile=$hookDist 2>$null
$ErrorActionPreference = $prevEAP

if (-not (Test-Path $hookDist)) {
    Write-Host "  BLAD: Kompilacja nie powiodla sie" -ForegroundColor Red
    Write-Host "  Zainstaluj esbuild: npm install -g esbuild" -ForegroundColor Yellow
    exit 1
}
Write-Host "  OK: $hookDist" -ForegroundColor Green

# 4. Backup i aktualizuj settings.json
Write-Host "`n[4/6] Aktualizacja settings.json..." -ForegroundColor Yellow

if (-not (Test-Path $settingsFile)) {
    Write-Host "  BLAD: Brak $settingsFile" -ForegroundColor Red
    exit 1
}

# Backup
Copy-Item $settingsFile "$settingsFile.backup" -Force
Write-Host "  Backup: $settingsFile.backup" -ForegroundColor Gray

$settings = Get-Content $settingsFile -Raw -Encoding UTF8 | ConvertFrom-Json

# Dodaj hook jesli nie istnieje
if (-not $settings.hooks) {
    $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue @{} -Force
}
if (-not $settings.hooks.PreToolUse) {
    $settings.hooks | Add-Member -NotePropertyName "PreToolUse" -NotePropertyValue @() -Force
}

# Sprawdz czy hook juz istnieje
$hookCommand = "node $($distDir.Replace('\', '/'))/safe-permissions.mjs"
$hookExists = $false
foreach ($entry in $settings.hooks.PreToolUse) {
    if ($entry.hooks) {
        foreach ($h in $entry.hooks) {
            if ($h.command -and $h.command -like "*safe-permissions*") {
                $hookExists = $true
                break
            }
        }
    }
}

if (-not $hookExists) {
    $newHook = @{
        matcher = "Bash"
        hooks = @(
            @{
                type = "command"
                command = $hookCommand
                timeout = 10
            }
        )
    }
    # Wstaw na poczatek (najwyzszy priorytet)
    $settings.hooks.PreToolUse = @($newHook) + @($settings.hooks.PreToolUse)
    Write-Host "  Hook dodany" -ForegroundColor Green
} else {
    Write-Host "  Hook juz istnieje" -ForegroundColor Yellow
}

# 5. Merge permissions
Write-Host "`n[5/6] Merge permissions..." -ForegroundColor Yellow
$permFile = "$claudeDir\settings-permissions.json"

if (Test-Path $permFile) {
    $fragment = Get-Content $permFile -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not $settings.permissions) {
        $settings | Add-Member -NotePropertyName "permissions" -NotePropertyValue @{} -Force
    }

    # Merge allow
    if ($fragment.permissions.allow) {
        $currentAllow = [System.Collections.Generic.HashSet[string]]::new()
        if ($settings.permissions.allow) {
            foreach ($r in $settings.permissions.allow) { [void]$currentAllow.Add($r) }
        }
        foreach ($r in $fragment.permissions.allow) { [void]$currentAllow.Add($r) }
        $settings.permissions.allow = @($currentAllow)
    }

    # Merge deny
    if ($fragment.permissions.deny) {
        $currentDeny = [System.Collections.Generic.HashSet[string]]::new()
        if ($settings.permissions.deny) {
            foreach ($r in $settings.permissions.deny) { [void]$currentDeny.Add($r) }
        }
        foreach ($r in $fragment.permissions.deny) { [void]$currentDeny.Add($r) }
        $settings.permissions.deny = @($currentDeny)
    }

    # Merge ask
    if ($fragment.permissions.ask) {
        if (-not $settings.permissions.ask) {
            $settings.permissions | Add-Member -NotePropertyName "ask" -NotePropertyValue @() -Force
        }
        $currentAsk = [System.Collections.Generic.HashSet[string]]::new()
        if ($settings.permissions.ask) {
            foreach ($r in $settings.permissions.ask) { [void]$currentAsk.Add($r) }
        }
        foreach ($r in $fragment.permissions.ask) { [void]$currentAsk.Add($r) }
        $settings.permissions.ask = @($currentAsk)
    }

    Write-Host "  Permissions zmergowane" -ForegroundColor Green
}

# Zapisz
$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
Write-Host "  Settings zapisane" -ForegroundColor Green

# 6. Dodaj funkcje ccd do profilu PowerShell
Write-Host "`n[6/6] Dodawanie komendy 'ccd'..." -ForegroundColor Yellow

$profilePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$profileDir = Split-Path $profilePath -Parent

# Utworz folder profilu jesli nie istnieje
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}

# Utworz profil jesli nie istnieje
if (-not (Test-Path $profilePath)) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$ccFunctions = @'

# === CC/CCD: Claude Code Launcher (safe-permissions addon) ===
# cc  = normalny tryb z git sync
# ccd = YOLO mode z git sync (--dangerously-skip-permissions)

function cc {
    param(
        [switch]$SkipGit,
        [switch]$SkipSync,
        [switch]$Force,
        [switch]$Dangerous  # Internal: YOLO mode
    )

    Write-Host ""

    # === 0. HISTORY SYNC (pull before session) ===
    $historyRepo = "$env:USERPROFILE\.claude-history"
    if (Test-Path "$historyRepo\.git") {
        Write-Host "Syncing history..." -ForegroundColor DarkGray -NoNewline
        Push-Location $historyRepo
        try {
            $localChanges = git status --porcelain 2>$null
            if ($localChanges) {
                git add -A 2>&1 | Out-Null
                git commit -m "Auto-commit before sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>&1 | Out-Null
            }
            $pullResult = git pull --rebase 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host " [OK]" -ForegroundColor DarkGray
            } else {
                Write-Host " [SKIP]" -ForegroundColor Yellow
            }
        } catch {
            Write-Host " [ERROR]" -ForegroundColor Red
        }
        Pop-Location
    }

    # === 1. GIT PULL (current project) ===
    if (-not $SkipGit -and (Test-Path ".git")) {
        $projectName = Split-Path (Get-Location) -Leaf
        Write-Host "Project: $projectName" -ForegroundColor Cyan

        $gitStatus = git status --porcelain 2>$null
        if ($gitStatus) {
            Write-Host "   Uncommitted changes" -ForegroundColor Yellow
        }

        $pull = Read-Host "   Pull latest? [Y/n]"
        if ($pull -notmatch "^[nN]") {
            $pullResult = git pull --rebase 2>&1
            if ($LASTEXITCODE -eq 0) {
                if ($pullResult -match "Already up to date") {
                    Write-Host "   [OK] Up to date" -ForegroundColor DarkGray
                } else {
                    Write-Host "   [OK] Pulled" -ForegroundColor Green
                }
            } else {
                Write-Host "   [X] Failed" -ForegroundColor Red
                $continue = Read-Host "   Continue? [y/N]"
                if ($continue -notmatch "^[yY]") { return }
            }
        }
        Write-Host ""
    }

    # === 2. LAUNCH CLAUDE ===
    if ($Dangerous) {
        Write-Host "Starting Claude (YOLO mode)..." -ForegroundColor Yellow
        Write-Host ""
        claude --dangerously-skip-permissions @args
    } else {
        Write-Host "Starting Claude..." -ForegroundColor Cyan
        Write-Host ""
        claude @args
    }

    # === 3. HISTORY SYNC (push after session) ===
    if (Test-Path "$historyRepo\.git") {
        Push-Location $historyRepo
        $changes = git status --porcelain 2>$null
        if ($changes) {
            Write-Host ""
            Write-Host "Pushing history..." -ForegroundColor DarkGray -NoNewline
            git add -A 2>&1 | Out-Null
            git commit -m "Session $(Get-Date -Format 'yyyy-MM-dd HH:mm')" 2>&1 | Out-Null
            $pushResult = git push 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host " [OK]" -ForegroundColor DarkGray
            } else {
                Write-Host " [SKIP]" -ForegroundColor Yellow
            }
        }
        Pop-Location
    }
}

function ccd {
    <#
    .SYNOPSIS
    Claude Code w YOLO mode z git sync.
    #>
    cc -Dangerous @args
}

function cc-fast { cc -SkipGit -SkipSync }
# =============================================================
'@

$currentProfile = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if (-not $currentProfile) { $currentProfile = "" }

# Usun stara wersje jesli istnieje
if ($currentProfile -match "# === CC/CCD:|# === CCD:") {
    Write-Host "  Usuwam stara wersje cc/ccd..." -ForegroundColor Yellow
    $currentProfile = $currentProfile -replace "(?s)# === CC.*?# ===+", ""
    Set-Content -Path $profilePath -Value $currentProfile.Trim() -Encoding UTF8
}

$currentProfile = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if ($currentProfile -notmatch "function cc \{") {
    Add-Content -Path $profilePath -Value $ccFunctions
    Write-Host "  Dodano funkcje cc/ccd do profilu" -ForegroundColor Green
} else {
    Write-Host "  Funkcje cc/ccd juz istnieja w profilu" -ForegroundColor Yellow
}

# Podsumowanie
Write-Host "`n=== Gotowe ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "4 warstwy ochrony aktywne:" -ForegroundColor White
Write-Host "  1. CATASTROPHIC - blokuje rm -rf /, dd, mkfs" -ForegroundColor Red
Write-Host "  2. CRITICAL     - chroni .git, node_modules, package.json" -ForegroundColor Yellow
Write-Host "  3. DELETE       - rm/rmdir -> trash" -ForegroundColor Blue
Write-Host "  4. SUSPICIOUS   - git push --force wymaga potwierdzenia" -ForegroundColor Magenta
Write-Host ""
Write-Host "Komendy:" -ForegroundColor White
Write-Host "  cc      - Claude z git sync (history pull/push, project pull)" -ForegroundColor Cyan
Write-Host "  ccd     - YOLO mode z git sync (--dangerously-skip-permissions)" -ForegroundColor Yellow
Write-Host "  cc-fast - cc bez git sync (-SkipGit -SkipSync)" -ForegroundColor Gray
Write-Host "  claude  - surowy Claude (bez git sync)" -ForegroundColor Gray
Write-Host ""
Write-Host "Uzyj: trash <plik> zamiast rm <plik>" -ForegroundColor White
Write-Host ""
Write-Host "WAZNE: Otworz nowy terminal zeby komendy zadzialaly!" -ForegroundColor Yellow
