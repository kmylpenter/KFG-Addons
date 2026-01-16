# ============================================================
# KFG Addons Installer v2.2
# ============================================================
# Modularny instalator dodatkow dla Claude Code
#
# v2.2: Fix dla katalogow kopiowanych do rodzica (np. skills/np/ -> skills/)
#       - Dodaje nazwe zrodlowego katalogu do relativePath
#       - Zapobiega blednym pominieniom przy duplicate detection
#
# v2.1: Fix dla pojedynczych plikow do ~/.claude/
#       - Poprawna obsluga plikow (nie tylko katalogow)
#       - Porownanie dat plik-do-pliku dla pojedynczych plikow
#
# v2.0: Inteligentne wykrywanie duplikatow i lokalizacji
#       - Sprawdza czy skill/target juz istnieje (globalnie/projektowo)
#       - Porownuje daty plikow - instaluje tylko jesli nowszy
#       - Instaluje do wlasciwej lokalizacji (projekt > global)
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File install-addons.ps1
#   powershell -ExecutionPolicy Bypass -File install-addons.ps1 -Addon migrate
#   powershell -ExecutionPolicy Bypass -File install-addons.ps1 -All
#   powershell -ExecutionPolicy Bypass -File install-addons.ps1 -All -Force
# ============================================================

param(
    [string]$Addon,           # Instaluj konkretny addon
    [switch]$All,             # Instaluj wszystkie
    [switch]$List,            # Tylko lista dostepnych
    [switch]$Force,           # Wymusz nadpisanie nawet jesli starszy
    [string]$TargetBase = $env:USERPROFILE
)

$ErrorActionPreference = "Stop"
$Version = "2.2.0"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonsDir = Join-Path $scriptDir "addons"

# ============================================================
# HELPER FUNCTIONS
# ============================================================

function Write-Banner {
    Write-Host ""
    Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |           KFG Addons Installer v$Version                     |" -ForegroundColor Cyan
    Write-Host "  |           Modular Add-ons for Claude Code                 |" -ForegroundColor Cyan
    Write-Host "  |           Smart duplicate detection enabled               |" -ForegroundColor DarkCyan
    Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Err { param([string]$Msg) Write-Host "    [X] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }
function Write-Skip { param([string]$Msg) Write-Host "    [~] $Msg" -ForegroundColor DarkGray }

# ============================================================
# DUPLICATE DETECTION FUNCTIONS (v2.0)
# ============================================================

function Find-ProjectClaudeDir {
    <#
    .SYNOPSIS
    Szuka projektowego .claude/ katalogu w parent directories
    Dynamicznie wykrywa na podstawie CWD i znanych wzorców
    #>

    # Dynamiczne wykrywanie projektów - szukaj w typowych lokalizacjach
    $projectRoots = @(
        "$env:USERPROFILE\Projects",
        "$env:USERPROFILE\projekty",
        "C:\Projekty",
        "D:\Projekty DELL KG",
        "D:\Projekty StriX"
    )

    # Znajdz istniejace rooty projektow
    foreach ($root in $projectRoots) {
        if (Test-Path $root) {
            $claudeDir = Join-Path $root ".claude"
            if (Test-Path $claudeDir) {
                return $claudeDir
            }
        }
    }

    # Fallback: szukaj od CWD w gore
    $current = Get-Location
    while ($current) {
        $claudeDir = Join-Path $current ".claude"
        if ((Test-Path $claudeDir) -and ($claudeDir -ne (Join-Path $env:USERPROFILE ".claude"))) {
            return $claudeDir
        }
        $parent = Split-Path $current -Parent
        if ($parent -eq $current) { break }
        $current = $parent
    }

    return $null
}

function Find-ExistingTarget {
    <#
    .SYNOPSIS
    Szuka czy target (np. skills/eos/) juz istnieje gdzies

    .RETURNS
    Hashtable z: Found, Location (project/global/none), Path
    #>
    param(
        [string]$TargetRelative  # np. "skills/eos/" lub "commands/yt.md"
    )

    $globalPath = Join-Path $TargetBase ".claude" | Join-Path -ChildPath $TargetRelative
    $projectClaudeDir = Find-ProjectClaudeDir

    # Sprawdz projektowy najpierw (priorytet)
    if ($projectClaudeDir) {
        $projectPath = Join-Path $projectClaudeDir $TargetRelative
        if (Test-Path $projectPath) {
            return @{
                Found = $true
                Location = "project"
                Path = $projectPath
                ProjectClaudeDir = $projectClaudeDir
            }
        }
    }

    # Sprawdz globalny
    if (Test-Path $globalPath) {
        return @{
            Found = $true
            Location = "global"
            Path = $globalPath
            ProjectClaudeDir = $projectClaudeDir
        }
    }

    return @{
        Found = $false
        Location = "none"
        Path = $null
        ProjectClaudeDir = $projectClaudeDir
    }
}

function Test-SourceNewer {
    <#
    .SYNOPSIS
    Porownuje daty plikow zrodla i celu

    .RETURNS
    $true jesli zrodlo jest nowsze, $false jesli cel jest nowszy lub rowny
    #>
    param(
        [string]$SourceDir,
        [string]$TargetDir
    )

    # Znajdz najnowszy plik w zrodle
    $sourceFiles = Get-ChildItem -Path $SourceDir -Recurse -File -ErrorAction SilentlyContinue
    if (-not $sourceFiles) { return $true }  # Brak plikow = instaluj

    $sourceNewest = $sourceFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    # Znajdz najnowszy plik w celu
    $targetFiles = Get-ChildItem -Path $TargetDir -Recurse -File -ErrorAction SilentlyContinue
    if (-not $targetFiles) { return $true }  # Cel pusty = instaluj

    $targetNewest = $targetFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    # Porownaj
    return $sourceNewest.LastWriteTime -gt $targetNewest.LastWriteTime
}

function Get-TargetRelativePath {
    <#
    .SYNOPSIS
    Wyciaga relatywna sciezke z target value (np. ~/.claude/skills/eos/ -> skills/eos/)
    #>
    param([string]$TargetValue)

    $normalized = $TargetValue -replace "~/\.claude/", "" -replace "~\\\.claude\\", ""
    $normalized = $normalized -replace "^/", "" -replace "^\\", ""
    return $normalized
}

# ============================================================
# ORIGINAL HELPER FUNCTIONS
# ============================================================

function Get-Addons {
    $addons = @()
    $addonFolders = Get-ChildItem -Path $addonsDir -Directory -ErrorAction SilentlyContinue

    foreach ($folder in $addonFolders) {
        $jsonPath = Join-Path $folder.FullName "addon.json"
        if (Test-Path $jsonPath) {
            try {
                $json = Get-Content $jsonPath -Raw | ConvertFrom-Json
                $addons += @{
                    Name = $json.name
                    DisplayName = $json.displayName
                    Description = $json.description
                    Version = $json.version
                    Dependencies = $json.dependencies
                    Targets = $json.targets
                    Scripts = $json.scripts
                    Path = $folder.FullName
                    Notes = $json.notes
                }
            } catch {
                Write-Warn "Blad parsowania $jsonPath"
            }
        }
    }
    return $addons
}

function Test-Dependency {
    param([string]$Name, [string]$MinVersion)

    switch ($Name) {
        "python" {
            try {
                $ver = python --version 2>&1 | Out-String
                if ($ver -match '(\d+\.\d+)') {
                    $current = $Matches[1]
                    if ([version]$current -ge [version]$MinVersion) {
                        return @{ OK = $true; Version = $current }
                    }
                    return @{ OK = $false; Version = $current; Required = $MinVersion }
                }
            } catch {}
            return @{ OK = $false; Version = $null }
        }
        "node" {
            try {
                $ver = node --version 2>&1 | Out-String
                if ($ver -match '(\d+)') {
                    return @{ OK = ([int]$Matches[1] -ge [int]$MinVersion); Version = $Matches[0] }
                }
            } catch {}
            return @{ OK = $false; Version = $null }
        }
        default {
            # Check if command exists
            try {
                $null = Get-Command $Name -ErrorAction Stop
                return @{ OK = $true; Version = "found" }
            } catch {
                return @{ OK = $false; Version = $null }
            }
        }
    }
}

function Install-PythonPackage {
    param([string]$Package)
    Write-Info "Instaluje pakiet Python: $Package"
    try {
        pip install $Package 2>&1 | Out-Null
        Write-OK "Zainstalowano: $Package"
        return $true
    } catch {
        Write-Err "Blad instalacji $Package"
        return $false
    }
}

function Install-Addon {
    param($Addon)

    Write-Host ""
    Write-Host "  Installing: $($Addon.DisplayName) v$($Addon.Version)" -ForegroundColor Yellow
    Write-Host "  -------------------------------------------------------------" -ForegroundColor DarkGray

    # Check dependencies
    if ($Addon.Dependencies) {
        foreach ($dep in $Addon.Dependencies.PSObject.Properties) {
            $depName = $dep.Name
            $depConfig = $dep.Value

            if ($depConfig.required) {
                $minVer = if ($depConfig.minVersion) { $depConfig.minVersion } else { "0" }
                $check = Test-Dependency -Name $depName -MinVersion $minVer

                if ($check.OK) {
                    Write-OK "Zaleznosc $depName OK ($($check.Version))"
                } else {
                    Write-Err "Brak zaleznosci: $depName (wymagane: $minVer)"

                    # Try to install
                    $install = Read-Host "    Zainstalowac $depName? [T/n]"
                    if ($install -eq "" -or $install -match "^[TtYy]") {
                        switch ($depName) {
                            "python" {
                                Write-Info "Instaluje Python przez winget..."
                                winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements
                                Write-Warn "Zrestartuj terminal po instalacji Python!"
                                return $false
                            }
                            "node" {
                                Write-Info "Instaluje Node.js przez winget..."
                                winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
                                Write-Warn "Zrestartuj terminal po instalacji Node!"
                                return $false
                            }
                        }
                    } else {
                        Write-Err "Pominieto - addon moze nie dzialac!"
                    }
                }

                # Install Python packages if needed
                if ($depName -eq "python" -and $depConfig.packages) {
                    foreach ($pkg in $depConfig.packages) {
                        Install-PythonPackage -Package $pkg
                    }
                }
            }
        }
    }

    # Copy files (v2.1: fix dla pojedynczych plikow do ~/.claude/)
    foreach ($target in $Addon.Targets.PSObject.Properties) {
        $sourcePath = Join-Path $Addon.Path $target.Name
        $targetValue = $target.Value

        if (-not (Test-Path $sourcePath)) {
            Write-Warn "Brak zrodla: $sourcePath"
            continue
        }

        # Sprawdz czy source to PLIK czy KATALOG
        $isSourceFile = Test-Path $sourcePath -PathType Leaf
        $sourceFileName = if ($isSourceFile) { Split-Path $sourcePath -Leaf } else { $null }
        $sourceDirName = if (-not $isSourceFile) { Split-Path $sourcePath -Leaf } else { $null }

        # Sprawdz czy to target do .claude/ (skills, commands, etc.)
        $isClaudeTarget = $targetValue -match "~/\.claude/" -or $targetValue -match "~\\\.claude\\"

        if ($isClaudeTarget) {
            # Wyciagnij relatywna sciezke (np. skills/eos/)
            $relativePath = Get-TargetRelativePath -TargetValue $targetValue

            # FIX v2.1: Dla pojedynczych plikow do ~/.claude/ (pusty relativePath)
            # Uzyj nazwy pliku zamiast pustego stringa
            if ($isSourceFile -and (-not $relativePath -or $relativePath -eq "")) {
                $relativePath = $sourceFileName
            }

            # FIX v2.2: Dla katalogow kopiowanych DO rodzica (np. skills/np/ -> skills/)
            # Dodaj nazwe zrodlowego katalogu do relativePath
            if (-not $isSourceFile -and $sourceDirName) {
                # Sprawdz czy relativePath juz zawiera nazwe katalogu
                if (-not $relativePath.TrimEnd('/\').EndsWith($sourceDirName)) {
                    $relativePath = Join-Path $relativePath $sourceDirName
                }
            }

            # Sprawdz czy juz istnieje gdzies
            $existing = Find-ExistingTarget -TargetRelative $relativePath

            if ($existing.Found) {
                # Juz istnieje - sprawdz czy mamy nowsza wersje
                # Dla plikow: porownaj plik z plikiem, nie katalog z katalogiem
                if ($isSourceFile) {
                    $sourceTime = (Get-Item $sourcePath).LastWriteTime
                    $targetTime = (Get-Item $existing.Path -ErrorAction SilentlyContinue).LastWriteTime
                    $isNewer = $sourceTime -gt $targetTime
                } else {
                    $isNewer = Test-SourceNewer -SourceDir $sourcePath -TargetDir $existing.Path
                }

                if (-not $isNewer -and -not $Force) {
                    Write-Skip "Pominieto: $relativePath (istniejacy w $($existing.Location) jest nowszy)"
                    continue
                }

                # Instaluj do ISTNIEJĄCEJ lokalizacji (nie twórz duplikatu!)
                # Dla plikow: targetPath to KATALOG (parent), nie sam plik
                if ($isSourceFile) {
                    $targetPath = Split-Path $existing.Path -Parent
                } else {
                    $targetPath = $existing.Path
                }
                $locationNote = if ($existing.Location -eq "project") { "-> projekt" } else { "-> global" }

                if ($isNewer) {
                    Write-Info "Aktualizuje: $relativePath $locationNote (nowsza wersja)"
                } else {
                    Write-Info "Nadpisuje: $relativePath $locationNote (--Force)"
                }
            } else {
                # Nie istnieje nigdzie - instaluj do globalnego (domyslnie)
                $targetPath = $targetValue -replace "~/", "$TargetBase\"
                $targetPath = $targetPath -replace "~\\", "$TargetBase\"
                Write-Info "Nowy: $relativePath -> global"
            }
        } else {
            # Nie-claude target (np. ~/.templates/) - standardowa logika
            $targetPath = $targetValue -replace "~/", "$TargetBase\"
            $targetPath = $targetPath -replace "~\\", "$TargetBase\"
        }

        # Utworz katalog docelowy jesli nie istnieje
        if (-not (Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }

        # Kopiuj - dla plikow nie uzywaj wildcard
        if ($isSourceFile) {
            Copy-Item -Path $sourcePath -Destination $targetPath -Force
        } else {
            Copy-Item -Path "$sourcePath*" -Destination $targetPath -Recurse -Force
        }
        Write-OK "Skopiowano: $($target.Name) -> $targetPath"
    }

    # Run postinstall script if defined
    if ($Addon.Scripts -and $Addon.Scripts.postinstall) {
        Write-Info "Uruchamiam postinstall script..."
        $postinstallCmd = $Addon.Scripts.postinstall -replace "%ADDON_DIR%", $Addon.Path
        try {
            Invoke-Expression $postinstallCmd
            Write-OK "Postinstall wykonany"
        } catch {
            Write-Warn "Blad postinstall: $_"
        }
    }

    if ($Addon.Notes) {
        Write-Host ""
        Write-Info "Uwagi: $($Addon.Notes)"
    }

    Write-OK "$($Addon.DisplayName) zainstalowany!"
    return $true
}

# ============================================================
# MAIN
# ============================================================

Write-Banner

# Get available addons
$addons = Get-Addons

if ($addons.Count -eq 0) {
    Write-Err "Nie znaleziono zadnych dodatkow w $addonsDir"
    exit 1
}

# List mode
if ($List) {
    Write-Host "  Dostepne dodatki:" -ForegroundColor White
    Write-Host ""
    foreach ($a in $addons) {
        Write-Host "    [$($a.Name)]" -ForegroundColor Cyan -NoNewline
        Write-Host " $($a.DisplayName) v$($a.Version)" -ForegroundColor White
        Write-Host "      $($a.Description)" -ForegroundColor Gray
    }
    Write-Host ""
    exit 0
}

# Single addon mode
if ($Addon) {
    $selected = $addons | Where-Object { $_.Name -eq $Addon }
    if (-not $selected) {
        Write-Err "Nie znaleziono dodatku: $Addon"
        Write-Host "  Dostepne: $($addons.Name -join ', ')" -ForegroundColor Gray
        exit 1
    }
    Install-Addon -Addon $selected
    exit 0
}

# All mode
if ($All) {
    Write-Host "  Instaluje wszystkie dodatki ($($addons.Count))..." -ForegroundColor White
    foreach ($a in $addons) {
        Install-Addon -Addon $a
    }
    Write-Host ""
    Write-OK "Wszystkie dodatki zainstalowane!"
    exit 0
}

# Interactive mode
Write-Host "  Dostepne dodatki:" -ForegroundColor White
Write-Host ""

for ($i = 0; $i -lt $addons.Count; $i++) {
    $a = $addons[$i]
    Write-Host "    [$($i+1)]" -ForegroundColor Cyan -NoNewline
    Write-Host " $($a.DisplayName)" -ForegroundColor White -NoNewline
    Write-Host " - $($a.Description)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "    [A] Zainstaluj wszystkie" -ForegroundColor Yellow
Write-Host "    [Q] Wyjdz" -ForegroundColor DarkGray
Write-Host ""

$choice = Read-Host "  Wybierz (numery oddzielone przecinkiem lub A)"

if ($choice -match "^[Qq]") {
    exit 0
}

if ($choice -match "^[Aa]") {
    foreach ($a in $addons) {
        Install-Addon -Addon $a
    }
} else {
    $indices = $choice -split "," | ForEach-Object { [int]$_.Trim() - 1 }
    foreach ($i in $indices) {
        if ($i -ge 0 -and $i -lt $addons.Count) {
            Install-Addon -Addon $addons[$i]
        }
    }
}

Write-Host ""
Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Green
Write-Host "  |           Instalacja zakonczona!                          |" -ForegroundColor Green
Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "  Nacisnij dowolny klawisz, aby zamknac..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
