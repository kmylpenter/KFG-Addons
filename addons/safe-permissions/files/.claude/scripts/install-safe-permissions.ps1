# Install Safe Permissions Addon v2
# Kompiluje hook rm->trash, merguje permissions

param([switch]$Force)

$ErrorActionPreference = "Stop"
$claudeDir = "$env:USERPROFILE\.claude"
$hooksDir = "$claudeDir\hooks"
$srcDir = "$hooksDir\src"
$distDir = "$hooksDir\dist"
$settingsFile = "$claudeDir\settings.json"

Write-Host "=== Safe Permissions v2 ===" -ForegroundColor Cyan

# 1. Sprawdz/zainstaluj trash-cli
Write-Host "`n[1/4] trash-cli..." -ForegroundColor Yellow
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
Write-Host "`n[2/4] esbuild..." -ForegroundColor Yellow
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
Write-Host "`n[3/5] Kompilacja hooka..." -ForegroundColor Yellow
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

# Kompiluj z esbuild (nie npx - juz zainstalowany globalnie)
# Tymczasowo wylacz ErrorActionPreference bo esbuild pisze do stderr
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
Write-Host "`n[4/5] Aktualizacja settings.json..." -ForegroundColor Yellow

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
Write-Host "`n[5/5] Merge permissions..." -ForegroundColor Yellow
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

# Podsumowanie
Write-Host "`n=== Gotowe ===" -ForegroundColor Cyan
Write-Host "- Hook blokuje rm/rmdir/del i sugeruje trash" -ForegroundColor White
Write-Host "- Uzyj: trash <plik> zamiast rm <plik>" -ForegroundColor White
Write-Host "- Restart Claude Code aby hook zadzialal" -ForegroundColor Yellow
