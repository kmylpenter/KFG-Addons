# ============================================================
# KFG Addons Installer v1.0
# ============================================================
# Modularny instalator dodatkow dla Claude Code
#
# Uzycie:
#   powershell -ExecutionPolicy Bypass -File install-addons.ps1
#   powershell -ExecutionPolicy Bypass -File install-addons.ps1 -Addon migrate
#   powershell -ExecutionPolicy Bypass -File install-addons.ps1 -All
# ============================================================

param(
    [string]$Addon,           # Instaluj konkretny addon
    [switch]$All,             # Instaluj wszystkie
    [switch]$List,            # Tylko lista dostepnych
    [string]$TargetBase = $env:USERPROFILE
)

$ErrorActionPreference = "Stop"
$Version = "1.0.0"
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
    Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

function Write-OK { param([string]$Msg) Write-Host "    [OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "    [!] $Msg" -ForegroundColor Yellow }
function Write-Err { param([string]$Msg) Write-Host "    [X] $Msg" -ForegroundColor Red }
function Write-Info { param([string]$Msg) Write-Host "    --> $Msg" -ForegroundColor Cyan }

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

    # Copy files
    foreach ($target in $Addon.Targets.PSObject.Properties) {
        $sourcePath = Join-Path $Addon.Path $target.Name
        $targetPath = $target.Value -replace "~/", "$TargetBase\"
        $targetPath = $targetPath -replace "~\\", "$TargetBase\"

        if (Test-Path $sourcePath) {
            # Create target directory
            if (-not (Test-Path $targetPath)) {
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            }

            # Copy recursively
            Copy-Item -Path "$sourcePath*" -Destination $targetPath -Recurse -Force
            Write-OK "Skopiowano: $($target.Name) -> $targetPath"
        } else {
            Write-Warn "Brak zrodla: $sourcePath"
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
