# Patch settings.json: statusline v8.1 + hooks registration
# Wywoływany jako postinstall przez install-addons.ps1
#
# BEZPIECZEŃSTWO (M8/M42/M55): plik settings.json usera jest krytyczny.
# Zasada: backup przed zapisem, nigdy ciche zniszczenie, nie wirować komend
# które padną (node). EAP=Stop + try/catch => błąd = exit 1, nie przepisanie.

$ErrorActionPreference = 'Stop'  # M8: bez tego rzucone błędy są pomijane, a plik i tak przepisywany

# M8: bezpieczne dodawanie property na PSCustomObject (ConvertFrom-Json).
# Bare `$obj.X = Y` rzuca "property cannot be found" gdy property nie istnieje.
# Add-Member -Force tworzy/nadpisuje NotePropertyName bez wyjątku.
function Ensure-Prop {
    param($Obj, [string]$Name, $Default)
    if (-not ($Obj.PSObject.Properties.Name -contains $Name)) {
        $Obj | Add-Member -NotePropertyName $Name -NotePropertyValue $Default -Force
    }
}

try {
    $settingsPath = "$env:USERPROFILE\.claude\settings.json"

    # M42: gdy settings.json nie istnieje — utwórz katalog ~/.claude + plik '{}' i kontynuuj
    if (-not (Test-Path $settingsPath)) {
        Write-Host "    [!] settings.json nie znaleziony — tworzę nowy" -ForegroundColor Yellow
        $claudeDir = Split-Path $settingsPath -Parent
        if (-not (Test-Path $claudeDir)) {
            New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($settingsPath, '{}', [System.Text.UTF8Encoding]::new($false))
    }

    $content = Get-Content $settingsPath -Raw
    $settings = $content | ConvertFrom-Json

    # M8: malformed/puste settings => $settings = $null. NIGDY nie zapisuj (literalny "null" nadpisałby plik).
    if ($null -eq $settings) {
        Write-Host "    [X] settings.json uszkodzony lub pusty — nie ruszam" -ForegroundColor Red
        exit 1
    }

    $changed = $false
    $userHome = $env:USERPROFILE -replace '\\', '/'

    # M55: statusLine i hooki wołają `node`. Bez Node na maszynie rejestracja
    # zmutowałaby settings.json by wołać nieistniejący `node` przy każdym renderze/edycji
    # (trwałe porażki spawn). Probe RAZ; brak node => pomijamy rejestrację, nie psujemy configu.
    $nodeAvailable = [bool](Get-Command node -ErrorAction SilentlyContinue)
    if (-not $nodeAvailable) {
        Write-Host "    [!] node nie znaleziony — pomijam rejestrację statusline/hooków" -ForegroundColor Yellow
    }

    if ($nodeAvailable) {
        # === 1. StatusLine command ===
        $newCmd = "node $userHome/.claude/statusline-wrapper.mjs"
        if (-not $settings.statusLine -or $settings.statusLine.command -ne $newCmd) {
            # M8: Add-Member zamiast bare dot-assignment (rzuca na PSCustomObject bez tej property)
            Ensure-Prop $settings 'statusLine' ([PSCustomObject]@{})
            $settings.statusLine = [PSCustomObject]@{ type = "command"; command = $newCmd }
            $changed = $true
            Write-Host "    [OK] statusLine -> $newCmd" -ForegroundColor Green
        } else {
            Write-Host "    [~] statusLine juz ustawiony" -ForegroundColor DarkGray
        }

        # === 2. PostToolUse hook: track-changed-files ===
        $trackCmd = "node $userHome/.claude/hooks/dist/track-changed-files.mjs"
        # M8: zapewnij hooks oraz hooks.PostToolUse jako property (zagnieżdżone — najpierw hooks)
        Ensure-Prop $settings 'hooks' ([PSCustomObject]@{})
        Ensure-Prop $settings.hooks 'PostToolUse' @()

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
            $editWriteEntry = $settings.hooks.PostToolUse | Where-Object { $_.matcher -eq 'Edit|Write' } | Select-Object -First 1
            if ($editWriteEntry) {
                $newHook = @{ type = "command"; command = $trackCmd; timeout = 3 }
                if ($editWriteEntry.PSObject.Properties.Name -contains 'hooks' -and $editWriteEntry.hooks) {
                    $hooksList = [System.Collections.ArrayList]@($editWriteEntry.hooks)
                    $hooksList.Add($newHook) | Out-Null
                    $editWriteEntry.hooks = $hooksList.ToArray()
                } else {
                    $editWriteEntry | Add-Member -NotePropertyName 'hooks' -NotePropertyValue @($newHook) -Force
                }
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
        # M8: Add-Member zamiast bare dot-assignment
        Ensure-Prop $settings.hooks 'UserPromptSubmit' @()

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
            if ($existingEntry) {
                $newHook = @{ type = "command"; command = $clearCmd; timeout = 2 }
                if ($existingEntry.PSObject.Properties.Name -contains 'hooks' -and $existingEntry.hooks) {
                    $hooksList = [System.Collections.ArrayList]@($existingEntry.hooks)
                    $hooksList.Add($newHook) | Out-Null
                    $existingEntry.hooks = $hooksList.ToArray()
                } else {
                    $existingEntry | Add-Member -NotePropertyName 'hooks' -NotePropertyValue @($newHook) -Force
                }
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
    }

    # === Save ===
    if ($changed) {
        # Backup PRZED zapisem (zasada usera: nigdy nie niszcz configu bez kopii)
        $backupPath = "$settingsPath.bak-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"
        Copy-Item $settingsPath $backupPath -Force
        Write-Host "    [OK] backup -> $backupPath" -ForegroundColor DarkGray

        $json = $settings | ConvertTo-Json -Depth 10
        # Write UTF-8 without BOM (PS5 Set-Content -Encoding UTF8 adds BOM which breaks JSON.parse in Node)
        [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
        Write-Host "    [OK] settings.json zapisany" -ForegroundColor Green
    } else {
        Write-Host "    [~] settings.json: brak zmian" -ForegroundColor DarkGray
    }

} catch {
    # M8: jakikolwiek błąd => czytelny komunikat + exit 1. NIGDY ciche przepisanie pliku.
    Write-Host "    [X] Blad patchowania settings.json: $_" -ForegroundColor Red
    Write-Host "    [!] settings.json NIE zostal zmodyfikowany (lub przywroc z .bak-*)" -ForegroundColor Yellow
    exit 1
}
