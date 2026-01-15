# Sound Notification - Patch settings.json to add hooks
# Adds Stop and Notification hooks for sound playback
# Compatible with PowerShell 5.x

param(
    [string]$SettingsPath = "$env:USERPROFILE\.claude\settings.json"
)

$ErrorActionPreference = "Stop"

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }

try {
    if (-not (Test-Path $SettingsPath)) {
        Write-Warn "settings.json nie istnieje: $SettingsPath"
        Write-Info "Musisz najpierw uruchomic Claude Code aby utworzyc settings.json"
        exit 1
    }

    Write-Info "Wczytuje: $SettingsPath"
    $content = Get-Content $SettingsPath -Raw

    # Check if hooks already exist
    if ($content -match "play-sound\.ps1") {
        Write-Warn "Hooki sound-notification juz istnieja - pomijam"
        exit 0
    }

    # Parse JSON using .NET (PS 5.x compatible)
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = 10MB
    $settings = $serializer.DeserializeObject($content)

    # Ensure hooks exists
    if (-not $settings.ContainsKey("hooks")) {
        $settings["hooks"] = @{}
    }

    $playCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%/.claude/hooks/notification/play-sound.ps1"'

    # Add Stop hook
    if (-not $settings["hooks"].ContainsKey("Stop")) {
        $settings["hooks"]["Stop"] = @(
            @{
                "matcher" = ""
                "hooks" = @(
                    @{
                        "type" = "command"
                        "command" = $playCmd
                        "timeout" = 5
                    }
                )
            }
        )
        Write-OK "Dodano hook: Stop"
    } else {
        Write-Warn "Hook Stop juz istnieje - pomijam"
    }

    # Add Notification hook
    if (-not $settings["hooks"].ContainsKey("Notification")) {
        $settings["hooks"]["Notification"] = @(
            @{
                "matcher" = "permission_prompt"
                "hooks" = @(
                    @{
                        "type" = "command"
                        "command" = $playCmd
                        "timeout" = 5
                    }
                )
            }
        )
        Write-OK "Dodano hook: Notification"
    } else {
        Write-Warn "Hook Notification juz istnieje - pomijam"
    }

    # Serialize back to JSON with formatting
    $json = $serializer.Serialize($settings)

    # Format JSON nicely (PS 5.x workaround)
    $json = $json | ConvertFrom-Json | ConvertTo-Json -Depth 10

    # Save with UTF8 encoding (no BOM for Claude compatibility)
    [System.IO.File]::WriteAllText($SettingsPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-OK "Zapisano: $SettingsPath"

} catch {
    Write-Host "    [X] Blad: $_" -ForegroundColor Red
    Write-Info "Dodaj recznie do settings.json w sekcji 'hooks':"
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
