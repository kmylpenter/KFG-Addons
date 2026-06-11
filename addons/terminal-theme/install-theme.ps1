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

# M12/M13: backup configu usera przed kazda modyfikacja (zasada: nie niszcz configu)
function Backup-Config {
    param([string]$Path)
    $ts = Get-Date -Format "yyyyMMdd-HHmmss"
    $bak = "$Path.bak-$ts"
    Copy-Item -Path $Path -Destination $bak -Force
    Write-Info "Backup: $bak"
}

# M13/M31: wykryj komentarze JSONC ('//' lub '/* */') ktore round-trip ConvertFrom/ConvertTo-Json zgubi
function Test-JsonHasComments {
    param([string]$Text)
    return ($Text -match '(?m)^\s*//') -or ($Text -match '(?m)//[^"\r\n]*$') -or ($Text -match '/\*')
}

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

# M12/M31: schemat jako obiekt (ordered) -> wstrzykiwany do sparsowanego JSON, nie przez regex.
# [ordered] zachowuje kolejnosc kluczy przy ConvertTo-Json (PS5.1-safe).
$kmylpenterScheme = [PSCustomObject]([ordered]@{
    name                = "KMYLPENTER"
    background          = $brand.Charcoal
    foreground          = $brand.OffWhite
    cursorColor         = $brand.BlueLight
    selectionBackground = $brand.Dark
    black               = $brand.Charcoal
    red                 = "#FF6B6B"
    green               = "#50FA7B"
    yellow              = "#F1FA8C"
    blue                = $brand.BlueDeep
    purple              = "#BD93F9"
    cyan                = $brand.BlueLight
    white               = $brand.OffWhite
    brightBlack         = $brand.Gray500
    brightRed           = "#FF8585"
    brightGreen         = "#69FF94"
    brightYellow        = "#FFFFA5"
    brightBlue          = $brand.BlueLight
    brightPurple        = "#D6ACFF"
    brightCyan          = $brand.BlueDeep
    brightWhite         = $brand.BlueDeep
})

# M12/M31: parsujemy JSON (brace-balanced przez parser), zamiast kruchych regexow.
#   - $wtFound  = czy settings.json w ogole istnieje (rozdzielony komunikat not-found vs patched)
#   - $wtInstalled = czy faktycznie cos zmodyfikowano/juz-skonfigurowano
$wtFound = $false
$wtInstalled = $false
foreach ($settingsPath in $wtSettingsPaths) {
    if (Test-Path $settingsPath) {
        $wtFound = $true
        Write-Info "Znaleziono: $settingsPath"
        try {
            $content = Get-Content $settingsPath -Raw

            # M13/M31: WT settings to JSONC; ConvertFrom/ConvertTo-Json zgubi komentarze usera
            if (Test-JsonHasComments $content) {
                Write-Warn "settings.json zawiera komentarze (//) - zostana usuniete przy zapisie (round-trip JSON)"
            }

            $settings = $content | ConvertFrom-Json

            # --- Krok 1: upewnij sie ze schemat KMYLPENTER istnieje w 'schemes' ---
            $schemeExists = $false
            if ($settings.PSObject.Properties.Name -contains 'schemes' -and $null -ne $settings.schemes) {
                foreach ($s in @($settings.schemes)) {
                    if ($s.name -eq 'KMYLPENTER') { $schemeExists = $true; break }
                }
            }

            if ($schemeExists) {
                Write-Warn "Schemat KMYLPENTER juz istnieje"
            } else {
                if ($settings.PSObject.Properties.Name -contains 'schemes' -and $null -ne $settings.schemes) {
                    # M31: dolacz do istniejacej tablicy (wymus tablice na PS5.1)
                    $settings.schemes = @($settings.schemes) + $kmylpenterScheme
                } else {
                    # M31: brak klucza 'schemes' (nowoczesny WT) -> utworz tablice
                    $settings | Add-Member -NotePropertyName 'schemes' -NotePropertyValue @($kmylpenterScheme) -Force
                }
                Write-OK "Dodano schemat KMYLPENTER"
            }

            # --- Krok 2: ustaw KMYLPENTER jako domyslny (profiles.defaults.colorScheme) ---
            # M12: robione na sparsowanym obiekcie ZAWSZE (takze gdy schemat juz istnial),
            #      wiec pol-aplikacji da sie dokonczyc przy re-run (brak wczesnego break).
            # M31: colorScheme ustawiamy tylko gdy schemat realnie jest obecny.
            if ($settings.PSObject.Properties.Name -contains 'profiles' -and $null -ne $settings.profiles) {
                if ($settings.profiles.PSObject.Properties.Name -notcontains 'defaults' -or $null -eq $settings.profiles.defaults) {
                    $settings.profiles | Add-Member -NotePropertyName 'defaults' -NotePropertyValue ([PSCustomObject]@{}) -Force
                }
                $defaults = $settings.profiles.defaults
                if ($defaults.PSObject.Properties.Name -contains 'colorScheme' -and $defaults.colorScheme -eq 'KMYLPENTER') {
                    Write-Warn "KMYLPENTER juz jest domyslnym schematem"
                } else {
                    $defaults | Add-Member -NotePropertyName 'colorScheme' -NotePropertyValue 'KMYLPENTER' -Force
                    Write-OK "Ustawiono KMYLPENTER jako domyslny schemat"
                }
            } else {
                Write-Warn "Brak sekcji 'profiles' - pomijam ustawienie domyslnego schematu"
            }

            # --- Zapis (z backupem) ---
            Backup-Config $settingsPath
            $json = $settings | ConvertTo-Json -Depth 100
            [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
            $wtInstalled = $true
        } catch {
            # M13: parse/zapis blad to NIE "nie znaleziony" - plik istnieje, ale nie udalo sie sparsowac
            Write-Warn "Blad przetwarzania settings.json (plik istnieje, ale nie zostal zmodyfikowany): $_"
        }
        break
    }
}

if (-not $wtFound) {
    Write-Warn "Windows Terminal nie znaleziony"
} elseif (-not $wtInstalled) {
    Write-Warn "Windows Terminal znaleziony, ale wystapil blad przy modyfikacji (config NIE zmieniony)"
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
    "terminal.border" = $brand.BlueLight            # Split terminal border
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

# M13: rozdziel "nie znaleziony" (plik nie istnieje) od "blad parsowania" (plik jest, ale JSONC sie wywalil)
$vscodeFound = $false
$vscodeInstalled = $false
foreach ($vscPath in $vscodeSettingsPaths) {
    if (Test-Path $vscPath) {
        $vscodeFound = $true
        Write-Info "Znaleziono: $vscPath"
        try {
            $content = Get-Content $vscPath -Raw

            # M13: settings.json VS Code to JSONC; round-trip ConvertFrom/ConvertTo-Json zgubi komentarze usera
            if (Test-JsonHasComments $content) {
                Write-Warn "settings.json zawiera komentarze (//) - zostana usuniete przy zapisie (round-trip JSON)"
            }

            $settings = $content | ConvertFrom-Json

            # M30: kontener jako [PSCustomObject]@{} (NIE Hashtable @{}) - inaczej Add-Member dodaje
            #      property ETS, ktorych ConvertTo-Json nie serializuje => pusty colorCustomizations.
            if (-not $settings."workbench.colorCustomizations") {
                $settings | Add-Member -NotePropertyName "workbench.colorCustomizations" -NotePropertyValue ([PSCustomObject]@{}) -Force
            }

            # Add terminal colors
            $colorCustom = $settings."workbench.colorCustomizations"

            # Always update colors (force overwrite)
            foreach ($key in $vscodeColors.Keys) {
                $colorCustom | Add-Member -NotePropertyName $key -NotePropertyValue $vscodeColors[$key] -Force
            }
            $settings."workbench.colorCustomizations" = $colorCustom
            Write-OK "Zaktualizowano kolory terminala KMYLPENTER"

            # Add terminal settings (drawBoldTextInBrightColors)
            foreach ($key in $vscodeTerminalSettings.Keys) {
                $settings | Add-Member -NotePropertyName $key -NotePropertyValue $vscodeTerminalSettings[$key] -Force
            }

            # M13: backup przed zapisem (zasada: nie niszcz configu)
            Backup-Config $vscPath
            $json = $settings | ConvertTo-Json -Depth 100   # -Depth 10 scinalo glebsze ustawienia usera do stringow (spojnie z WT)
            [System.IO.File]::WriteAllText($vscPath, $json, [System.Text.UTF8Encoding]::new($false))
            Write-OK "Ustawiono terminal.integrated.drawBoldTextInBrightColors"
            $vscodeInstalled = $true
        } catch {
            # M13: plik istnieje, ale parse/zapis sie nie udal - to NIE "nie znaleziony"
            Write-Warn "Blad przetwarzania settings.json (plik istnieje, ale nie zostal zmodyfikowany): $_"
        }
        break
    }
}

if (-not $vscodeFound) {
    Write-Warn "VS Code nie znaleziony"
    Write-Info "Dodaj recznie do VS Code settings.json:"
    Write-Host "  workbench.colorCustomizations z kolorami terminal.*" -ForegroundColor Gray
}

# ============================================================
# 3. WINDOWS 11 ACCENT COLOR (osobny skrypt)
# ============================================================
Write-Header "Windows 11 Accent Color"
Write-Info "Wydzielono do osobnego skryptu (moze triggerowac AV)"
Write-Info "Uruchom recznie: set-windows-accent.ps1"

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
