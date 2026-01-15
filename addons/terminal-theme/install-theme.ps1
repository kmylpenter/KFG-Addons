# KMYLPENTER Terminal Theme Installer
# Adds brand color scheme to Windows Terminal

$ErrorActionPreference = "Stop"

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }

# Windows Terminal settings paths
$wtSettingsPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
)

# KMYLPENTER Brand Color Scheme
$kmylpenterScheme = @{
    name = "KMYLPENTER"

    # Background & Foreground (brand darks)
    background = "#0d1117"           # --charcoal
    foreground = "#f6f8fa"           # --off-white
    cursorColor = "#3A90C8"          # --blue-light
    selectionBackground = "#161b22"  # --dark

    # Standard colors (row 0-7)
    black = "#0d1117"                # charcoal
    red = "#EC5F67"                  # error red (standard)
    green = "#99C794"                # success green (standard)
    yellow = "#FAC863"               # warning yellow (standard)
    blue = "#076AAC"                 # --blue-deep (brand!)
    purple = "#C594C5"               # purple (standard)
    cyan = "#3A90C8"                 # --blue-light (brand!)
    white = "#f6f8fa"                # --off-white

    # Bright colors (row 8-15)
    brightBlack = "#6e7681"          # --gray-500
    brightRed = "#FF6673"
    brightGreen = "#A3D995"
    brightYellow = "#FFD580"
    brightBlue = "#3A90C8"           # --blue-light (brand!)
    brightPurple = "#D6A6D6"
    brightCyan = "#5FCCCC"           # lighter cyan
    brightWhite = "#FFFFFF"
}

# Find Windows Terminal settings
$settingsPath = $null
foreach ($path in $wtSettingsPaths) {
    if (Test-Path $path) {
        $settingsPath = $path
        break
    }
}

if (-not $settingsPath) {
    Write-Warn "Windows Terminal nie znaleziony"
    Write-Info "Schemat kolorow KMYLPENTER:"
    Write-Host ($kmylpenterScheme | ConvertTo-Json -Depth 5) -ForegroundColor Gray
    Write-Info "Dodaj recznie do Windows Terminal settings.json w sekcji 'schemes'"
    exit 1
}

Write-Info "Znaleziono Windows Terminal: $settingsPath"

try {
    # Read current settings
    $content = Get-Content $settingsPath -Raw

    # Remove comments (WT supports // and /* */ comments)
    $cleanContent = $content -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''

    # Parse JSON
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = 10MB
    $settings = $serializer.DeserializeObject($cleanContent)

    # Ensure schemes array exists
    if (-not $settings.ContainsKey("schemes")) {
        $settings["schemes"] = @()
    }

    # Check if KMYLPENTER scheme already exists
    $existingScheme = $settings["schemes"] | Where-Object { $_.name -eq "KMYLPENTER" }

    if ($existingScheme) {
        Write-Warn "Schemat KMYLPENTER juz istnieje - aktualizuje"
        $settings["schemes"] = $settings["schemes"] | Where-Object { $_.name -ne "KMYLPENTER" }
    }

    # Add new scheme
    $settings["schemes"] += $kmylpenterScheme
    Write-OK "Dodano schemat: KMYLPENTER"

    # Serialize back to JSON
    $json = $serializer.Serialize($settings)
    $json = $json | ConvertFrom-Json | ConvertTo-Json -Depth 10

    # Save
    [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
    Write-OK "Zapisano: $settingsPath"

} catch {
    Write-Host "    [X] Blad: $_" -ForegroundColor Red
    Write-Info "Schemat kolorow KMYLPENTER (dodaj recznie):"
    Write-Host ($kmylpenterScheme | ConvertTo-Json -Depth 5) -ForegroundColor Gray
    exit 1
}

Write-Host ""
Write-Info "Schemat KMYLPENTER zainstalowany!"
Write-Info ""
Write-Info "Aby aktywowac:"
Write-Info "  1. Otworz Windows Terminal Settings (Ctrl+,)"
Write-Info "  2. Profiles > Defaults (lub konkretny profil)"
Write-Info "  3. Appearance > Color scheme > KMYLPENTER"
Write-Info ""
Write-Info "Kolory brand:"
Write-Info "  Cyan/Blue: #3A90C8 (--blue-light)"
Write-Info "  Blue:      #076AAC (--blue-deep)"
Write-Info "  Background:#0d1117 (--charcoal)"
