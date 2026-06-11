# Sound Notification - Patch settings.json to add hooks
# Adds Stop and Notification hooks for sound playback
# Compatible with PowerShell 5.x
#
# BEZPIECZEŃSTWO (M9/M42): settings.json usera jest krytyczny.
# - M9: gdy event (Stop/Notification) już istnieje => APPEND wpisu do listy,
#       nie SKIP całości (schema CC = lista wpisów {matcher,hooks[]} per event).
# - M42: gdy plik nie istnieje => utwórz ~/.claude + '{}', kontynuuj patch.
# - backup przed zapisem.

param(
    [string]$SettingsPath = "$env:USERPROFILE\.claude\settings.json"
)

$ErrorActionPreference = "Stop"

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }

# M9: zwraca $true jeśli komenda play-sound figuruje już w którymkolwiek wpisie eventu
# (idempotencja — nie dubluj wpisu przy ponownym uruchomieniu).
function Test-HasPlayHook {
    param($EventList)
    if ($null -eq $EventList) { return $false }
    foreach ($entry in $EventList) {
        if ($entry -and $entry.ContainsKey('hooks') -and $entry['hooks']) {
            foreach ($h in $entry['hooks']) {
                if ($h -and $h.ContainsKey('command') -and ($h['command'] -match 'play-sound')) {
                    return $true
                }
            }
        }
    }
    return $false
}

try {
    # M42: gdy settings.json nie istnieje — utwórz katalog ~/.claude + plik '{}' i kontynuuj
    if (-not (Test-Path $SettingsPath)) {
        Write-Warn "settings.json nie istnieje — tworzę nowy: $SettingsPath"
        $claudeDir = Split-Path $SettingsPath -Parent
        if (-not (Test-Path $claudeDir)) {
            New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($SettingsPath, '{}', [System.Text.UTF8Encoding]::new($false))
    }

    Write-Info "Wczytuje: $SettingsPath"
    $content = Get-Content $SettingsPath -Raw

    # Parse JSON using .NET (PS 5.x compatible) — daje Dictionary<string,object>, tablice jako object[]
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = 10MB
    $settings = $serializer.DeserializeObject($content)

    # M9/bezpieczeństwo: uszkodzony/pusty/nie-obiektowy JSON => nie ruszamy pliku.
    if (($null -eq $settings) -or (-not ($settings -is [System.Collections.IDictionary]))) {
        Write-Host "    [X] settings.json uszkodzony lub nie jest obiektem — nie ruszam" -ForegroundColor Red
        exit 1
    }

    $changed = $false

    # Ensure hooks exists
    if (-not $settings.ContainsKey("hooks")) {
        $settings["hooks"] = @{}
    }
    $hooks = $settings["hooks"]

    $playCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%/.claude/hooks/notification/play-sound.ps1"'

    # Wzorce wpisów do dodania (per event)
    $stopEntry = @{
        "matcher" = ""
        "hooks" = @(
            @{ "type" = "command"; "command" = $playCmd; "timeout" = 5 }
        )
    }
    $notificationEntry = @{
        "matcher" = "permission_prompt"
        "hooks" = @(
            @{ "type" = "command"; "command" = $playCmd; "timeout" = 5 }
        )
    }

    # === Stop hook ===
    if (-not $hooks.ContainsKey("Stop")) {
        $hooks["Stop"] = @($stopEntry)
        $changed = $true
        Write-OK "Dodano hook: Stop"
    } elseif (Test-HasPlayHook $hooks["Stop"]) {
        # M9: nasza komenda już figuruje — idempotentnie pomijamy (bez dublowania)
        Write-Warn "Hook Stop z play-sound juz istnieje - pomijam"
    } else {
        # M9: event Stop istnieje, ale BEZ naszego dźwięku => APPEND wpisu do listy
        # (nie skip-całości — user z własnym Stop hookiem ma dalej dostać dźwięk)
        $list = [System.Collections.ArrayList]@($hooks["Stop"])
        $list.Add($stopEntry) | Out-Null
        $hooks["Stop"] = $list.ToArray()
        $changed = $true
        Write-OK "Dopisano wpis play-sound do istniejacego hooka: Stop"
    }

    # === Notification hook ===
    if (-not $hooks.ContainsKey("Notification")) {
        $hooks["Notification"] = @($notificationEntry)
        $changed = $true
        Write-OK "Dodano hook: Notification"
    } elseif (Test-HasPlayHook $hooks["Notification"]) {
        # M9: idempotencja
        Write-Warn "Hook Notification z play-sound juz istnieje - pomijam"
    } else {
        # M9: APPEND zamiast skip-całości
        $list = [System.Collections.ArrayList]@($hooks["Notification"])
        $list.Add($notificationEntry) | Out-Null
        $hooks["Notification"] = $list.ToArray()
        $changed = $true
        Write-OK "Dopisano wpis play-sound do istniejacego hooka: Notification"
    }

    if (-not $changed) {
        Write-Warn "Hooki sound-notification juz aktualne - brak zmian"
        exit 0
    }

    # Serialize back to JSON with formatting
    $json = $serializer.Serialize($settings)

    # Format JSON nicely (PS 5.x workaround)
    $json = $json | ConvertFrom-Json | ConvertTo-Json -Depth 10

    # Backup PRZED zapisem (zasada usera: nigdy nie niszcz configu bez kopii)
    $backupPath = "$SettingsPath.bak-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"
    Copy-Item $SettingsPath $backupPath -Force
    Write-Host "    [OK] backup -> $backupPath" -ForegroundColor DarkGray

    # Save with UTF8 encoding (no BOM for Claude compatibility)
    [System.IO.File]::WriteAllText($SettingsPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-OK "Zapisano: $SettingsPath"

} catch {
    Write-Host "    [X] Blad: $_" -ForegroundColor Red
    Write-Info "settings.json NIE zostal zmodyfikowany (lub przywroc z .bak-*). Dodaj recznie w sekcji 'hooks':"
    Write-Host @'
    "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"%USERPROFILE%/.claude/hooks/notification/play-sound.ps1\"", "timeout": 5 }] }],
    "Notification": [{ "matcher": "permission_prompt", "hooks": [{ "type": "command", "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"%USERPROFILE%/.claude/hooks/notification/play-sound.ps1\"", "timeout": 5 }] }]
'@ -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Info "Sound notification aktywny!"
Write-Info "Dzwiek: C:\Windows\Media\notify.wav"
Write-Info "Triggery: Stop (koniec pracy), Notification (permission_prompt)"
