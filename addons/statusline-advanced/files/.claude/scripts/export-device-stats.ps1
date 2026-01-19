# Export Device Stats for Cross-Device Totals
# v6.0: Simplified - aggregates per-user stats from totals-history.json
#
# Flow:
# 1. Run analyze-history.ps1 to update totals
# 2. Aggregate stats per user from sessions
# 3. Save to ~/.claude-history/stats/user-{name}.json
# 4. Git commit & push

param(
    [switch]$SkipAnalyze,
    [switch]$Verbose
)

$ErrorActionPreference = 'SilentlyContinue'

# === CONFIG ===
$configPath = "$env:USERPROFILE\.config\kfg-stats\users.json"
$statsDir = "$env:USERPROFILE\.claude-history\stats"
$analyzeScript = "$env:USERPROFILE\.claude\analyze-history.ps1"
$totalsFile = "$env:USERPROFILE\.claude\totals-history.json"

Write-Host ""
Write-Host "=== Export User Stats v6.0 ===" -ForegroundColor Cyan

# === LOAD CONFIG ===
function Load-Config {
    if (-not (Test-Path $configPath)) {
        Write-Host "BLAD: Brak konfiguracji $configPath" -ForegroundColor Red
        Write-Host "Uruchom kfg-settings aby skonfigurowac uzytkownikow" -ForegroundColor Yellow
        return $null
    }
    try {
        $json = Get-Content $configPath -Raw | ConvertFrom-Json
        $config = @{
            defaultUser = $json.defaultUser
            users = @{}
            folderMapping = @{}
        }
        if ($json.users) {
            foreach ($prop in $json.users.PSObject.Properties) {
                $config.users[$prop.Name] = $prop.Value
            }
        }
        if ($json.folderMapping) {
            foreach ($prop in $json.folderMapping.PSObject.Properties) {
                $config.folderMapping[$prop.Name] = $prop.Value
            }
        }
        Write-Host "  Config: $($config.users.Count) users, $($config.folderMapping.Count) folder mappings" -ForegroundColor DarkGray
        return $config
    } catch {
        Write-Host "BLAD: Nie mozna wczytac konfiguracji: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# === MAIN ===
$config = Load-Config
if (-not $config) { exit 1 }

Write-Host ""

# === CREATE STATS DIR ===
if (-not (Test-Path $statsDir)) {
    New-Item -ItemType Directory -Path $statsDir -Force | Out-Null
    Write-Host "Utworzono: $statsDir" -ForegroundColor Gray
}

# === RUN ANALYZE-HISTORY ===
if (-not $SkipAnalyze -and (Test-Path $analyzeScript)) {
    Write-Host "Uruchamiam analyze-history.ps1..." -ForegroundColor Gray
    & $analyzeScript
    Write-Host ""
}

# === LOAD TOTALS ===
if (-not (Test-Path $totalsFile)) {
    Write-Host "BLAD: Brak pliku $totalsFile" -ForegroundColor Red
    Write-Host "Uruchom najpierw: analyze-history.ps1" -ForegroundColor Yellow
    exit 1
}

$totals = Get-Content $totalsFile -Raw | ConvertFrom-Json

# === AGGREGATE PER USER ===
$userStats = @{}

# Initialize all users
foreach ($userName in $config.users.Keys) {
    $userStats[$userName] = @{
        user = $userName
        lastUpdate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        duration_ms = [long]0
        tokens_main = [long]0
        tokens_total = [long]0
        agent_savings = [long]0
        chars_user = [long]0
        chars_ai = [long]0
        cost = [double]0
        sessions = [int]0
        messages = [int]0
        user_prompts = [int]0
    }
}

# Aggregate from sessions
if ($totals.sessions) {
    foreach ($prop in $totals.sessions.PSObject.Properties) {
        $session = $prop.Value
        $user = $session.user
        if (-not $user) { $user = $config.defaultUser }

        if (-not $userStats.ContainsKey($user)) {
            # User not in config, add them
            $userStats[$user] = @{
                user = $user
                lastUpdate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                duration_ms = [long]0
                tokens_main = [long]0
                tokens_total = [long]0
                agent_savings = [long]0
                chars_user = [long]0
                chars_ai = [long]0
                cost = [double]0
                sessions = [int]0
                messages = [int]0
                user_prompts = [int]0
            }
        }

        $userStats[$user].duration_ms += [long]$session.duration_ms
        $userStats[$user].tokens_main += [long]$session.tokens_main
        $userStats[$user].tokens_total += [long]$session.tokens_total
        $userStats[$user].agent_savings += [long]$session.agent_savings
        $userStats[$user].chars_user += [long]$(if ($session.chars_user) { $session.chars_user } else { 0 })
        $userStats[$user].chars_ai += [long]$(if ($session.chars_ai) { $session.chars_ai } else { 0 })
        $userStats[$user].cost += [double]$session.cost
        $userStats[$user].sessions++
        $userStats[$user].messages += [int]$session.messages
        $userStats[$user].user_prompts += [int]$session.user_prompts
    }
}

# === SAVE PER USER FILES ===
Write-Host "=== Zapisano pliki uzytkownikow ===" -ForegroundColor Green
Write-Host ""

foreach ($userName in $userStats.Keys) {
    $stats = $userStats[$userName]
    $userFile = Join-Path $statsDir "user-$userName.json"
    $stats | ConvertTo-Json -Depth 3 | Out-File -FilePath $userFile -Encoding UTF8

    $totalMs = $stats.duration_ms
    $days = [math]::Floor($totalMs / 86400000)
    $hours = [math]::Floor(($totalMs % 86400000) / 3600000)
    $tokMainM = [math]::Round($stats.tokens_main / 1000000, 2)
    $costStr = "`$" + [math]::Round($stats.cost, 2)

    Write-Host "  $userName" -ForegroundColor Yellow
    Write-Host "    Czas:     ${days}d ${hours}h" -ForegroundColor White
    Write-Host "    Tokeny:   ${tokMainM}M" -ForegroundColor Cyan
    Write-Host "    Koszt:    $costStr" -ForegroundColor Magenta
    Write-Host "    Sesje:    $($stats.sessions)" -ForegroundColor White
    Write-Host ""
}

# === GIT COMMIT & PUSH ===
$historyRepo = "$env:USERPROFILE\.claude-history"
if (Test-Path "$historyRepo\.git") {
    Push-Location $historyRepo
    try {
        git add "stats/user-*.json" 2>$null
        $hasChanges = git diff --cached --quiet 2>$null; $hasChanges = $LASTEXITCODE -ne 0
        if ($hasChanges) {
            git commit -m "stats: update user stats" --quiet 2>$null
            git pull --quiet 2>$null
            git push --quiet 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Git: committed & pushed to claude-history" -ForegroundColor DarkGray
            } else {
                Write-Host "Git: commit OK, push failed (sprawdz recznie)" -ForegroundColor DarkYellow
            }
        } else {
            Write-Host "Git: no changes to commit" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "Git: error - $($_.Exception.Message)" -ForegroundColor DarkRed
    }
    Pop-Location
}

Write-Host ""
