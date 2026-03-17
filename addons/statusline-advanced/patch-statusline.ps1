# Patch settings.json: statusline v8.1 + hooks registration
# Wywoływany jako postinstall przez install-addons.ps1

$settingsPath = "$env:USERPROFILE\.claude\settings.json"
if (-not (Test-Path $settingsPath)) {
    Write-Host "    [!] settings.json nie znaleziony" -ForegroundColor Yellow
    return
}

$content = Get-Content $settingsPath -Raw
$settings = $content | ConvertFrom-Json
$changed = $false
$userHome = $env:USERPROFILE -replace '\\', '/'

# === 1. StatusLine command ===
$newCmd = "node $userHome/.claude/statusline-wrapper.mjs"
if (-not $settings.statusLine -or $settings.statusLine.command -ne $newCmd) {
    $settings.statusLine = @{ type = "command"; command = $newCmd }
    $changed = $true
    Write-Host "    [OK] statusLine -> $newCmd" -ForegroundColor Green
} else {
    Write-Host "    [~] statusLine juz ustawiony" -ForegroundColor DarkGray
}

# === 2. PostToolUse hook: track-changed-files ===
$trackCmd = "node $userHome/.claude/hooks/dist/track-changed-files.mjs"
if (-not $settings.hooks) { $settings.hooks = @{} }
if (-not $settings.hooks.PostToolUse) { $settings.hooks.PostToolUse = @() }

$hasTrackHook = $false
foreach ($entry in $settings.hooks.PostToolUse) {
    if ($entry.hooks) {
        foreach ($h in $entry.hooks) {
            if ($h.command -match 'track-changed-files') { $hasTrackHook = $true }
        }
    }
}

if (-not $hasTrackHook) {
    # Find existing Edit|Write entry or create new
    $editWriteEntry = $settings.hooks.PostToolUse | Where-Object { $_.matcher -eq 'Edit|Write' }
    if ($editWriteEntry) {
        $hooksList = [System.Collections.ArrayList]@($editWriteEntry.hooks)
        $hooksList.Add(@{ type = "command"; command = $trackCmd; timeout = 3 }) | Out-Null
        $editWriteEntry.hooks = $hooksList.ToArray()
    } else {
        $settings.hooks.PostToolUse += @{
            matcher = "Edit|Write"
            hooks = @(@{ type = "command"; command = $trackCmd; timeout = 3 })
        }
    }
    $changed = $true
    Write-Host "    [OK] PostToolUse: track-changed-files registered" -ForegroundColor Green
} else {
    Write-Host "    [~] PostToolUse: track-changed-files juz zarejestrowany" -ForegroundColor DarkGray
}

# === 3. UserPromptSubmit hook: clear-changed-files ===
$clearCmd = "node $userHome/.claude/hooks/dist/clear-changed-files.mjs"
if (-not $settings.hooks.UserPromptSubmit) { $settings.hooks.UserPromptSubmit = @() }

$hasClearHook = $false
foreach ($entry in $settings.hooks.UserPromptSubmit) {
    if ($entry.hooks) {
        foreach ($h in $entry.hooks) {
            if ($h.command -match 'clear-changed-files') { $hasClearHook = $true }
        }
    }
}

if (-not $hasClearHook) {
    # Find existing entry or create new
    $existingEntry = $settings.hooks.UserPromptSubmit | Select-Object -First 1
    if ($existingEntry -and $existingEntry.hooks) {
        $hooksList = [System.Collections.ArrayList]@($existingEntry.hooks)
        $hooksList.Add(@{ type = "command"; command = $clearCmd; timeout = 2 }) | Out-Null
        $existingEntry.hooks = $hooksList.ToArray()
    } else {
        $settings.hooks.UserPromptSubmit += @{
            hooks = @(@{ type = "command"; command = $clearCmd; timeout = 2 })
        }
    }
    $changed = $true
    Write-Host "    [OK] UserPromptSubmit: clear-changed-files registered" -ForegroundColor Green
} else {
    Write-Host "    [~] UserPromptSubmit: clear-changed-files juz zarejestrowany" -ForegroundColor DarkGray
}

# === Save ===
if ($changed) {
    $json = $settings | ConvertTo-Json -Depth 10
    # Write UTF-8 without BOM (PS5 Set-Content -Encoding UTF8 adds BOM which breaks JSON.parse in Node)
    [System.IO.File]::WriteAllText($settingsPath, $json)
    Write-Host "    [OK] settings.json zapisany" -ForegroundColor Green
} else {
    Write-Host "    [~] settings.json: brak zmian" -ForegroundColor DarkGray
}
