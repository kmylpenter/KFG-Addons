# Export Device Stats for Cross-Device Totals
# Generuje device-{ID}.json z lokalnymi statystykami
# v4.0: DeviceId = USERNAME (matches analyze-history cwd logic)
#       Eksportuje chars_user, chars_ai dla nowych wskaźników
# v2.0: Filtrowanie po urzadzeniu - eksportuje TYLKO dane z tego urzadzenia

param(
    [string]$RepoPath = "",  # Auto-detect: ~/.claude parent (KFG repo) or D:\Projekty StriX\KFG
    [string]$DeviceId = $env:COMPUTERNAME,  # Device ID for stats (configure in kfgsettings)
    [switch]$SkipAnalyze
)

# Auto-detect KFG repo path if not provided
if (-not $RepoPath -or -not (Test-Path $RepoPath)) {
    # Try: PSScriptRoot/.../stats (when installed to ~/.claude/)
    $kfgFromInstalled = Join-Path (Split-Path $PSScriptRoot -Parent) "stats"

    # Try: KFG repo in common locations (StriX, DELL, Projekty)
    $kfgRepoPaths = @(
        "D:\Projekty StriX\KFG",
        "D:\Projekty DELL KG\KFG",
        "C:\Projekty\KFG"
    )

    if (Test-Path $kfgFromInstalled) {
        $RepoPath = Split-Path $kfgFromInstalled -Parent
        Write-Host "Wykryto KFG repo: $RepoPath" -ForegroundColor Gray
    } else {
        $found = $false
        foreach ($kfgRepo in $kfgRepoPaths) {
            if (Test-Path "$kfgRepo\stats") {
                $RepoPath = $kfgRepo
                Write-Host "Wykryto KFG repo: $RepoPath" -ForegroundColor Gray
                $found = $true
                break
            }
        }
        if (-not $found) {
            Write-Host "BLAD: Nie znaleziono KFG repo ze stats/" -ForegroundColor Red
            exit 1
        }
    }
}

$ErrorActionPreference = 'SilentlyContinue'

# Sciezki
$deviceHistoryFile = "$env:USERPROFILE\.claude\totals-$DeviceId.json"  # Per-device history
$analyzeScript = "$env:USERPROFILE\.claude\analyze-history.ps1"
$statsDir = Join-Path $RepoPath "stats"
$deviceFile = Join-Path $statsDir "device-$DeviceId.json"

Write-Host ""
Write-Host "=== Export Device Stats ===" -ForegroundColor Cyan
Write-Host "Device ID: $DeviceId" -ForegroundColor Yellow
Write-Host ""

# 1. Uruchom analyze-history.ps1 z filtrem dla TEGO urzadzenia
if (-not $SkipAnalyze -and (Test-Path $analyzeScript)) {
    Write-Host "Uruchamiam analyze-history.ps1 -DeviceFilter $DeviceId..." -ForegroundColor Gray
    & $analyzeScript -DeviceFilter $DeviceId -OutputFile $deviceHistoryFile
    Write-Host ""
}

# Fallback: jesli brak per-device, uzyj globalnego (ale to bedzie cross-device!)
$historyFile = if (Test-Path $deviceHistoryFile) { $deviceHistoryFile } else { "$env:USERPROFILE\.claude\totals-history.json" }

# 2. Sprawdz czy mamy dane
if (-not (Test-Path $historyFile)) {
    Write-Host "BLAD: Brak pliku $historyFile" -ForegroundColor Red
    Write-Host "Uruchom najpierw: analyze-history.ps1" -ForegroundColor Yellow
    exit 1
}

# 3. Wczytaj dane
$history = Get-Content $historyFile -Raw | ConvertFrom-Json

# 4. Przygotuj podsumowanie dla tego urzadzenia
# v4.0: dodano chars_user, chars_ai
$deviceStats = @{
    deviceId = $DeviceId
    lastUpdate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    duration_ms = [long]$history.total_duration_ms
    tokens_main = [long]$history.total_tokens_main
    tokens_total = [long]$history.total_tokens_total
    agent_savings = [long]$history.total_agent_savings
    chars_user = if ($history.total_chars_user) { [long]$history.total_chars_user } else { 0 }
    chars_ai = if ($history.total_chars_ai) { [long]$history.total_chars_ai } else { 0 }
    cost = [double]$history.total_cost
    sessions = [int]$history.analysis_stats.sessions_found
    messages = [int]$history.analysis_stats.messages_total
    user_prompts = [int]$history.analysis_stats.user_prompts_total
}

# 5. Utworz folder stats jesli nie istnieje
if (-not (Test-Path $statsDir)) {
    New-Item -ItemType Directory -Path $statsDir -Force | Out-Null
}

# 6. Zapisz device-{ID}.json
$deviceStats | ConvertTo-Json -Depth 3 | Out-File -FilePath $deviceFile -Encoding UTF8

# 6.5 Kopiuj też do ~/.claude/stats/ (wrapper czyta stamtąd priorytetowo)
$localStatsDir = "$env:USERPROFILE\.claude\stats"
if (-not (Test-Path $localStatsDir)) {
    New-Item -ItemType Directory -Path $localStatsDir -Force | Out-Null
}
Copy-Item $deviceFile -Destination $localStatsDir -Force

# 7. Wyswietl podsumowanie
$totalMs = $deviceStats.duration_ms
$days = [math]::Floor($totalMs / 86400000)
$hours = [math]::Floor(($totalMs % 86400000) / 3600000)
$tokMainM = [math]::Round($deviceStats.tokens_main / 1000000, 2)
$tokTotalM = [math]::Round($deviceStats.tokens_total / 1000000, 2)
$agentSavingsM = [math]::Round($deviceStats.agent_savings / 1000000, 2)

Write-Host "=== Zapisano: $deviceFile ===" -ForegroundColor Green
Write-Host ""
Write-Host "  Czas:          ${days}d ${hours}h" -ForegroundColor Yellow
Write-Host "  Tokeny main:   ${tokMainM}M" -ForegroundColor Cyan
Write-Host "  Tokeny total:  ${tokTotalM}M" -ForegroundColor Cyan
Write-Host "  Agent savings: ${agentSavingsM}M" -ForegroundColor Blue
Write-Host "  Koszt:         `$$([math]::Round($deviceStats.cost, 2))" -ForegroundColor Magenta
Write-Host "  Sesje:         $($deviceStats.sessions)" -ForegroundColor White
Write-Host ""

# 8. Git commit & push (jeśli w repo KFG)
if ($kfgRepo) {
    Push-Location $kfgRepo
    try {
        git add "stats/device-*.json" 2>$null
        $hasChanges = git diff --cached --quiet 2>$null; $hasChanges = $LASTEXITCODE -ne 0
        if ($hasChanges) {
            git commit -m "stats: update device-$DeviceId" --quiet 2>$null
            git push --quiet 2>$null
            Write-Host "Git: committed & pushed" -ForegroundColor DarkGray
        }
    } catch { }
    Pop-Location
}

# 9. Zwroc sciezke do pliku (dla dalszego uzycia)
return $deviceFile

