# KMYLPENTER Terminal Theme Installer v2.0
# Installs brand colors to:
#   1. Windows Terminal (color scheme)
#   2. VS Code Terminal (color customizations)
#   3. Windows 11 Accent Color (optional)

$ErrorActionPreference = "Stop"

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }
function Write-Header { param([string]$Msg) Write-Host "`n  === $Msg ===" -ForegroundColor Yellow }

# ============================================================
# BRAND COLORS
# ============================================================
$brand = @{
    BlueLight = "#3A90C8"
    BlueDeep = "#076AAC"
    Charcoal = "#0d1117"
    Dark = "#161b22"
    OffWhite = "#f6f8fa"
    Gray500 = "#6e7681"
}

# ============================================================
# 1. WINDOWS TERMINAL
# ============================================================
Write-Header "Windows Terminal"

$wtSettingsPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

$kmylpenterSchemeJson = @"
{
    "name": "KMYLPENTER",
    "background": "$($brand.Charcoal)",
    "foreground": "$($brand.OffWhite)",
    "cursorColor": "$($brand.BlueLight)",
    "selectionBackground": "$($brand.Dark)",
    "black": "$($brand.Charcoal)",
    "red": "#FF6B6B",
    "green": "#50FA7B",
    "yellow": "#F1FA8C",
    "blue": "$($brand.BlueDeep)",
    "purple": "#BD93F9",
    "cyan": "$($brand.BlueLight)",
    "white": "$($brand.OffWhite)",
    "brightBlack": "$($brand.Gray500)",
    "brightRed": "#FF8585",
    "brightGreen": "#69FF94",
    "brightYellow": "#FFFFA5",
    "brightBlue": "$($brand.BlueLight)",
    "brightPurple": "#D6ACFF",
    "brightCyan": "#5FCCCC",
    "brightWhite": "#FFFFFF"
}
"@

$wtInstalled = $false
foreach ($settingsPath in $wtSettingsPaths) {
    if (Test-Path $settingsPath) {
        Write-Info "Znaleziono: $settingsPath"
        try {
            $content = Get-Content $settingsPath -Raw

            if ($content -match '"name"\s*:\s*"KMYLPENTER"') {
                Write-Warn "Schemat KMYLPENTER juz istnieje"
                $wtInstalled = $true
                break
            }

            if ($content -match '("schemes"\s*:\s*\[)(\s*)') {
                $insertPoint = $Matches[0]
                $indent = "        "
                $schemeLines = $kmylpenterSchemeJson -split "`n" | ForEach-Object { "$indent$($_.Trim())" }
                $indentedScheme = $schemeLines -join "`n"

                if ($content -match '"schemes"\s*:\s*\[\s*\]') {
                    $replacement = "`"schemes`": [`n$indentedScheme`n    ]"
                    $content = $content -replace '"schemes"\s*:\s*\[\s*\]', $replacement
                } else {
                    $replacement = "$insertPoint`n$indentedScheme,"
                    $content = $content -replace [regex]::Escape($insertPoint), $replacement
                }

                [System.IO.File]::WriteAllText($settingsPath, $content, [System.Text.UTF8Encoding]::new($false))
                Write-OK "Dodano schemat KMYLPENTER"
                $wtInstalled = $true
            }

            # Set KMYLPENTER as default color scheme
            $content = Get-Content $settingsPath -Raw
            if ($content -notmatch '"colorScheme"\s*:\s*"KMYLPENTER"') {
                # Add colorScheme to profiles.defaults
                if ($content -match '("defaults"\s*:\s*\{)(\s*)(\})') {
                    # Empty defaults - add colorScheme
                    $content = $content -replace '("defaults"\s*:\s*\{)(\s*)(\})', "`$1`n                    `"colorScheme`": `"KMYLPENTER`"`n                `$3"
                    [System.IO.File]::WriteAllText($settingsPath, $content, [System.Text.UTF8Encoding]::new($false))
                    Write-OK "Ustawiono KMYLPENTER jako domyslny schemat"
                } elseif ($content -match '("defaults"\s*:\s*\{[^}]+)(\})') {
                    # Non-empty defaults - append colorScheme
                    $content = $content -replace '("defaults"\s*:\s*\{[^}]+)(\})', "`$1,`n                    `"colorScheme`": `"KMYLPENTER`"`n                `$2"
                    [System.IO.File]::WriteAllText($settingsPath, $content, [System.Text.UTF8Encoding]::new($false))
                    Write-OK "Ustawiono KMYLPENTER jako domyslny schemat"
                }
            } else {
                Write-Warn "KMYLPENTER juz jest domyslnym schematem"
            }
        } catch {
            Write-Warn "Blad: $_"
        }
        break
    }
}

if (-not $wtInstalled) {
    Write-Warn "Windows Terminal nie znaleziony lub blad instalacji"
}

# ============================================================
# 2. VS CODE TERMINAL
# ============================================================
Write-Header "VS Code Terminal"

$vscodeSettingsPaths = @(
    "$env:APPDATA\Code\User\settings.json",
    "$env:APPDATA\Code - Insiders\User\settings.json"
)

$vscodeColors = @{
    "terminal.background" = $brand.Charcoal
    "terminal.foreground" = $brand.OffWhite
    "terminalCursor.foreground" = $brand.BlueLight
    "terminal.selectionBackground" = $brand.Dark
    "terminal.ansiBlack" = $brand.Charcoal
    "terminal.ansiRed" = "#FF6B6B"
    "terminal.ansiGreen" = "#50FA7B"
    "terminal.ansiYellow" = "#F1FA8C"
    "terminal.ansiBlue" = $brand.BlueLight          # Links
    "terminal.ansiMagenta" = "#BD93F9"
    "terminal.ansiCyan" = $brand.BlueLight
    "terminal.ansiWhite" = $brand.OffWhite
    "terminal.ansiBrightBlack" = $brand.Gray500
    "terminal.ansiBrightRed" = "#FF8585"
    "terminal.ansiBrightGreen" = "#69FF94"
    "terminal.ansiBrightYellow" = "#FFFFA5"
    "terminal.ansiBrightBlue" = $brand.BlueLight
    "terminal.ansiBrightMagenta" = "#D6ACFF"
    "terminal.ansiBrightCyan" = $brand.BlueDeep     # Inline code (brand deep)
    "terminal.ansiBrightWhite" = $brand.BlueDeep    # Bold text (brand deep)
}

# Additional VS Code terminal settings
$vscodeTerminalSettings = @{
    "terminal.integrated.drawBoldTextInBrightColors" = $true
}

$vscodeInstalled = $false
foreach ($vscPath in $vscodeSettingsPaths) {
    if (Test-Path $vscPath) {
        Write-Info "Znaleziono: $vscPath"
        try {
            $content = Get-Content $vscPath -Raw
            $settings = $content | ConvertFrom-Json

            # Ensure workbench.colorCustomizations exists
            if (-not $settings."workbench.colorCustomizations") {
                $settings | Add-Member -NotePropertyName "workbench.colorCustomizations" -NotePropertyValue @{} -Force
            }

            # Add terminal colors
            $colorCustom = $settings."workbench.colorCustomizations"
            $hasKmylpenter = $colorCustom."terminal.background" -eq $brand.Charcoal

            if ($hasKmylpenter) {
                Write-Warn "Kolory KMYLPENTER juz istnieja"
            } else {
                foreach ($key in $vscodeColors.Keys) {
                    $colorCustom | Add-Member -NotePropertyName $key -NotePropertyValue $vscodeColors[$key] -Force
                }
                $settings."workbench.colorCustomizations" = $colorCustom
                Write-OK "Dodano kolory terminala KMYLPENTER"
            }

            # Add terminal settings (drawBoldTextInBrightColors)
            foreach ($key in $vscodeTerminalSettings.Keys) {
                $settings | Add-Member -NotePropertyName $key -NotePropertyValue $vscodeTerminalSettings[$key] -Force
            }

            $json = $settings | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($vscPath, $json, [System.Text.UTF8Encoding]::new($false))
            Write-OK "Ustawiono terminal.integrated.drawBoldTextInBrightColors"
            $vscodeInstalled = $true
        } catch {
            Write-Warn "Blad: $_"
        }
        break
    }
}

if (-not $vscodeInstalled) {
    Write-Warn "VS Code nie znaleziony"
    Write-Info "Dodaj recznie do VS Code settings.json:"
    Write-Host "  workbench.colorCustomizations z kolorami terminal.*" -ForegroundColor Gray
}

# ============================================================
# 3. WINDOWS 11 ACCENT COLOR (OPTIONAL)
# ============================================================
Write-Header "Windows 11 Accent Color (Opcjonalne)"

Write-Host ""
Write-Host "    Czy chcesz ustawic kolor akcentu Windows 11 na KMYLPENTER Blue?" -ForegroundColor White
Write-Host "    (#3A90C8 - pasek zadan, ramki okien, przyciski)" -ForegroundColor Gray
Write-Host ""
$choice = Read-Host "    Ustawic? [t/N]"

if ($choice -match "^[TtYy]") {
    try {
        # Convert hex to BGR (Windows uses BGR format)
        # #3A90C8 -> RGB(58, 144, 200) -> BGR: 0x00C8903A
        $blueLight = 0x00C8903A

        # Set accent color in registry
        $dwmPath = "HKCU:\SOFTWARE\Microsoft\Windows\DWM"
        $themePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"

        # Enable custom accent color
        Set-ItemProperty -Path $dwmPath -Name "AccentColor" -Value $blueLight -Type DWord -Force
        Set-ItemProperty -Path $dwmPath -Name "ColorizationColor" -Value $blueLight -Type DWord -Force
        Set-ItemProperty -Path $dwmPath -Name "ColorizationAfterglow" -Value $blueLight -Type DWord -Force

        # Set color prevalence (show accent color on title bars and window borders)
        Set-ItemProperty -Path $dwmPath -Name "ColorPrevalence" -Value 1 -Type DWord -Force

        # Enable accent color on Start and taskbar
        if (Test-Path $themePath) {
            Set-ItemProperty -Path $themePath -Name "ColorPrevalence" -Value 1 -Type DWord -Force
        }

        Write-OK "Ustawiono kolor akcentu Windows 11"
        Write-Info "Moze wymagac wylogowania/ponownego uruchomienia"

    } catch {
        Write-Warn "Blad ustawiania akcentu: $_"
        Write-Info "Ustaw recznie: Ustawienia > Personalizacja > Kolory > Kolor akcentu"
    }
} else {
    Write-Info "Pominieto Windows 11 accent color"
}

# ============================================================
# SUMMARY
# ============================================================
Write-Host ""
Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "  |           KMYLPENTER Theme - Podsumowanie                 |" -ForegroundColor Cyan
Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
Write-Host "    Kolory brand:" -ForegroundColor White
Write-Host "      Blue Light:  $($brand.BlueLight) (cyan, akcenty)" -ForegroundColor Cyan
Write-Host "      Blue Deep:   $($brand.BlueDeep) (blue, CTA)" -ForegroundColor Blue
Write-Host "      Charcoal:    $($brand.Charcoal) (background)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "    Windows Terminal: KMYLPENTER ustawiony jako default" -ForegroundColor Green
Write-Host "    VS Code terminal: kolory automatycznie aktywne" -ForegroundColor Green
Write-Host ""
Write-Host "    Uruchom ponownie terminal aby zobaczyc zmiany!" -ForegroundColor Yellow
Write-Host ""
