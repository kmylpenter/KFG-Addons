# ============================================================
# KFG Addons Installer v2.3
# ============================================================
# Modularny instalator dodatkow dla Claude Code
#
# v2.6: Fix: tworzenie katalogu zamiast pliku dla nowych pojedynczych plikow
#       - Dla plikow targetPath to KATALOG (parent), nie sciezka samego pliku
#       - Auto-cleanup: jesli poprzednia wersja utworzyla katalog zamiast pliku,
#         zostaje wykryty i usuniety przed kopiowaniem
#
# v2.5: ensureEnv - automatyczne ustawianie zmiennych env w settings.json
#       - Addon moze deklarowac wymagane env vars w addon.json
#       - Installer sprawdza i dodaje brakujace do settings.json
#
# v2.4: Fix kopiowania pojedynczych plikow do podkatalogow ~/.claude/
#       - relativePath teraz zawsze zawiera nazwe pliku (nie tylko katalog)
#       - Naprawia pomijanie plikow jak clear-changed-files.mjs
#
# v2.3: Automatyczny backup przed nadpisaniem plikow
#       - Tworzy backup z timestampem (file.backup-YYYY-MM-DD-HHmm)
#       - Tylko dla istniejacych plikow (nie dla katalogow)
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
$Version = "2.6.0"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonsDir = Join-Path $scriptDir "addons"

# ============================================================
# HELPER FUNCTIONS
# ============================================================

function Write-Banner {
    Write-Host ""
    Write-Host "  +-----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |           KFG Addons Installer v$Version                    |" -ForegroundColor Cyan
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
    Szuka projektowego .claude/ katalogu idac w gore od CWD (ancestor-walk).
    #>

    # M33: ancestor-walk od CWD jako JEDYNE zrodlo prawdy.
    # (Usunieto hardkodowana liste rootow maszyny autora - znajdowala .claude w
    #  korzeniu kontenera/dysku i lokowala instalacje, w tym hooki auto-exec, w
    #  obcym projekcie. .claude musi nalezec do realnego projektu nad CWD.)
    $globalClaude = Join-Path $TargetBase ".claude"
    $current = (Get-Location).Path
    while ($current) {
        $claudeDir = Join-Path $current ".claude"
        if ((Test-Path -LiteralPath $claudeDir -PathType Container) -and ($claudeDir -ne $globalClaude)) {
            return $claudeDir
        }
        $parent = Split-Path $current -Parent
        if (-not $parent -or $parent -eq $current) { break }  # korzen dysku
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
# SETTINGS.JSON ENV MANAGEMENT (v2.5)
# ============================================================

function Ensure-SettingsEnv {
    <#
    .SYNOPSIS
    Sprawdza i dodaje zmienne srodowiskowe do settings.json
    Uzywa addon.json pole "ensureEnv" do deklaracji wymaganych zmiennych
    #>
    param(
        [hashtable]$EnvVars  # np. @{ "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" = "1" }
    )

    if (-not $EnvVars -or $EnvVars.Count -eq 0) { return }

    $settingsPath = Join-Path $TargetBase ".claude\settings.json"

    if (-not (Test-Path $settingsPath)) {
        Write-Warn "Brak settings.json: $settingsPath"
        return
    }

    try {
        $settingsRaw = Get-Content -LiteralPath $settingsPath -Raw
        $settings = $settingsRaw | ConvertFrom-Json

        # M11: walidacja - jesli JSON pusty/uszkodzony ConvertFrom-Json zwraca $null; nie nadpisuj
        if ($null -eq $settings) {
            Write-Err "settings.json pusty lub niepoprawny JSON - pomijam aktualizacje env"
            return
        }

        # Upewnij sie ze sekcja env istnieje
        if (-not $settings.env) {
            $settings | Add-Member -NotePropertyName "env" -NotePropertyValue ([PSCustomObject]@{})
        }

        $changed = $false
        foreach ($key in $EnvVars.Keys) {
            $value = $EnvVars[$key]
            $currentValue = $settings.env.$key

            if ($currentValue -eq $value) {
                Write-OK "Env $key = $value (juz ustawione)"
            } else {
                if ($currentValue) {
                    Write-Info "Env ${key}: $currentValue -> $value"
                } else {
                    Write-Info "Env $key = $value (dodaje)"
                }
                $settings.env | Add-Member -NotePropertyName $key -NotePropertyValue $value -Force
                $changed = $true
            }
        }

        if ($changed) {
            # M11: backup przed zapisem cudzego configu
            $bkp = "$settingsPath.backup-$(Get-Date -Format 'yyyy-MM-dd-HHmm')"
            Copy-Item -LiteralPath $settingsPath -Destination $bkp -Force
            Write-Info "Backup: $bkp"
            # M11: WriteAllText bez BOM (PS5 Set-Content -Encoding UTF8 dodaje BOM, ktory lamie JSON.parse w Node)
            $json = $settings | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
            Write-OK "Zaktualizowano settings.json (env)"
        }
    } catch {
        Write-Err "Blad aktualizacji settings.json: $_"
    }
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
                $json = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
                $addons += @{
                    Name = $json.name
                    DisplayName = $json.displayName
                    Description = $json.description
                    Version = $json.version
                    Dependencies = $json.dependencies
                    Targets = $json.targets
                    Scripts = $json.scripts
                    ensureEnv = $json.ensureEnv
                    Platform = $json.platform   # M3: termux|termux+proot|any|windows|brak(=any)
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

# M27: bezpieczne parsowanie wersji - normalizuje '0'->'0.0', '18'->'18.0' i odporne na smieci.
# [version] wymaga min. jednej kropki; bezkropkowe/puste wartosci rzucaja, wiec TryParse z paddingiem.
function ConvertTo-SafeVersion {
    param([string]$Raw)
    if (-not $Raw) { $Raw = "0" }
    $Raw = ($Raw -replace '[^\d\.].*$', '').Trim()   # utnij ogon (np. '1.2-rc' -> '1.2'), zostaw cyfry/kropki
    if ($Raw -eq "") { $Raw = "0" }
    if ($Raw -notmatch '\.') { $Raw = "$Raw.0" }     # '18' -> '18.0'
    [version]$parsed = $null
    if ([version]::TryParse($Raw, [ref]$parsed)) { return $parsed }
    return [version]"0.0"
}

function Test-Dependency {
    param([string]$Name, [string]$MinVersion)

    switch ($Name) {
        "python" {
            try {
                $ver = python --version 2>&1 | Out-String
                if ($ver -match '(\d+\.\d+)') {
                    $current = $Matches[1]
                    # M27: normalizuj obie strony zanim porownasz (puste/bezkropkowe minVer nie moga rzucac)
                    if ((ConvertTo-SafeVersion $current) -ge (ConvertTo-SafeVersion $MinVersion)) {
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
                    # M27: minVer typu '18.17' nie zmiesci sie w [int] - porownaj jako wersje
                    $ok = (ConvertTo-SafeVersion $Matches[1]) -ge (ConvertTo-SafeVersion $MinVersion)
                    return @{ OK = $ok; Version = $Matches[0] }
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
        # M1/M29: pip to natywny proces - try/catch go NIE lapie. Sprawdz $LASTEXITCODE.
        $global:LASTEXITCODE = 0
        pip install $Package 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Zainstalowano: $Package"
            return $true
        }
        Write-Err "Blad instalacji $Package (pip exit $LASTEXITCODE)"
        return $false
    } catch {
        Write-Err "Blad instalacji $Package : $_"
        return $false
    }
}

function Install-NpmPackage {
    param([string]$Package)
    Write-Info "Instaluje pakiet npm: $Package"
    try {
        # M32: npm to natywny proces - sprawdz $LASTEXITCODE (try/catch nie wystarczy).
        $global:LASTEXITCODE = 0
        npm install -g $Package 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-OK "Zainstalowano: $Package"
            return $true
        }
        Write-Err "Blad instalacji $Package (npm exit $LASTEXITCODE)"
        return $false
    } catch {
        Write-Err "Blad instalacji $Package : $_"
        return $false
    }
}

# M20/M47/M52: kontrola traversal i rozwijanie celu sa zrobione INLINE w petli
# targetow (Install-Addon) — zweryfikowana logika dziala dla wszystkich realnych
# ksztaltow targetow. Guard '..' przy starcie iteracji odrzuca traversal w kluczu
# i wartosci zanim cokolwiek skopiujemy.

# M3: czy addon pasuje do hosta. Tu (.ps1) host = Windows. Akceptuj platformy
# zawierajace 'windows' lub 'any'; brak pola = 'any'.
function Test-HostPlatform {
    param([string]$Platform)
    if (-not $Platform -or $Platform.Trim() -eq "") { return $true }   # brak = any
    $p = $Platform.ToLower()
    return ($p -match 'windows' -or $p -match 'any')
}

function Install-Addon {
    param($Addon)

    Write-Host ""
    Write-Host "  Installing: $($Addon.DisplayName) v$($Addon.Version)" -ForegroundColor Yellow
    Write-Host "  -------------------------------------------------------------" -ForegroundColor DarkGray

    # M3: pomin addony niepasujace do platformy Windows
    if (-not (Test-HostPlatform $Addon.Platform)) {
        Write-Skip "Pomijam $($Addon.Name) - platforma '$($Addon.Platform)' nie obejmuje windows/any"
        return $true   # pominiecie to nie blad
    }

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
                # M32: node packages — wczesniej dokumentowane ale nieinstalowane
                if ($depName -eq "node" -and $depConfig.packages) {
                    foreach ($pkg in $depConfig.packages) {
                        Install-NpmPackage -Package $pkg
                    }
                }
            }
        }
    }

    # Copy files (v2.1: fix dla pojedynczych plikow do ~/.claude/)
    foreach ($target in $Addon.Targets.PSObject.Properties) {
        # M17: inicjalizuj $existing per-iteracja. Bylo ustawiane tylko w galezi
        # isClaudeTarget, a konsumowane PO niej (backup ~631, cleanup ~621) -> dla
        # nie-claude targetu czytalo $existing z POPRZEDNIej iteracji (zly backup),
        # a jako pierwszy target -> $null.Found rzucalo pod EAP=Stop.
        $existing = @{ Found = $false; Path = $null; Location = "none" }
        $sourcePath = Join-Path $Addon.Path $target.Name
        $targetValue = $target.Value

        # M20/M52: odrzuc traversal w KLUCZU (zrodlo) i WARTOSCI (cel) zanim cokolwiek skopiujemy
        if ($target.Name -match '\.\.' -or $targetValue -match '\.\.') {
            Write-Err "Pomijam target z '..' (traversal): $($target.Name) -> $targetValue"
            continue
        }

        if (-not (Test-Path -LiteralPath $sourcePath)) {
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

            # FIX v2.1+v2.4: Dla pojedynczych plikow - dodaj nazwe pliku do relativePath
            # v2.1: pusty relativePath -> uzyj nazwy pliku
            # v2.4: niepusty relativePath (np. hooks/dist/) -> dolacz nazwe pliku
            if ($isSourceFile) {
                if (-not $relativePath -or $relativePath -eq "") {
                    $relativePath = $sourceFileName
                } elseif (-not $relativePath.EndsWith($sourceFileName)) {
                    $relativePath = Join-Path $relativePath $sourceFileName
                }
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
                    $sourceTime = (Get-Item -LiteralPath $sourcePath).LastWriteTime
                    $targetTime = (Get-Item -LiteralPath $existing.Path -ErrorAction SilentlyContinue).LastWriteTime
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
                # v2.6: dla pojedynczych plikow targetPath to KATALOG (parent), nie sam plik
                if ($isSourceFile) {
                    $targetPath = Split-Path $targetPath -Parent
                }
                Write-Info "Nowy: $relativePath -> global"
            }
        } else {
            # Nie-claude target (np. ~/.templates/) - standardowa logika
            $targetPath = $targetValue -replace "~/", "$TargetBase\"
            $targetPath = $targetPath -replace "~\\", "$TargetBase\"
            if ($isSourceFile) {
                $targetPath = Split-Path $targetPath -Parent
            }
        }

        # v2.6: Wykryj i napraw przypadek gdy poprzednia wersja utworzyla
        # sciezke pliku jako katalog (bug z v2.5 i wczesniejszych)
        if ($isSourceFile) {
            $expectedFilePath = Join-Path $targetPath (Split-Path $sourcePath -Leaf)
            if ((Test-Path -LiteralPath $expectedFilePath) -and (Test-Path -LiteralPath $expectedFilePath -PathType Container)) {
                # M36: NIE kasuj rekursywnie (heurystyka; w WinPS5.1 -Recurse na junction/symlink
                # kasuje ZAWARTOSC celu). Kwarantanna przez rename + guard ReparsePoint.
                $attrs = (Get-Item -LiteralPath $expectedFilePath -Force).Attributes
                if ($attrs -band [System.IO.FileAttributes]::ReparsePoint) {
                    Write-Warn "Sciezka to symlink/junction: $expectedFilePath — NIE ruszam, pomijam target"
                    continue
                }
                $quar = "$expectedFilePath.corrupt-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"
                Write-Warn "Wykryto katalog zamiast pliku: $expectedFilePath -> kwarantanna $quar"
                Rename-Item -LiteralPath $expectedFilePath -NewName (Split-Path $quar -Leaf)
                # cleanup uniewaznia detekcje - po przeniesieniu traktuj jako nowy plik
                $existing.Found = $false
            }
        }

        # Utworz katalog docelowy jesli nie istnieje
        if (-not (Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        }

        # Backup przed nadpisaniem (v2.3) - tylko gdy istniejacy plik jest faktycznie plikiem
        if ($existing.Found -and $isSourceFile -and (Test-Path $existing.Path -PathType Leaf)) {
            $backupPath = "$($existing.Path).backup-$(Get-Date -Format 'yyyy-MM-dd-HHmm')"
            Copy-Item -LiteralPath $existing.Path -Destination $backupPath -Force
            Write-Info "Backup: $backupPath"
        }

        # Kopiuj - dla plikow nie uzywaj wildcard
        if ($isSourceFile) {
            Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        } else {
            Copy-Item -Path "$sourcePath*" -Destination $targetPath -Recurse -Force
        }
        Write-OK "Skopiowano: $($target.Name) -> $targetPath"
    }

    # Ensure env vars in settings.json (v2.5)
    if ($Addon.ensureEnv) {
        Write-Info "Sprawdzam wymagane zmienne srodowiskowe..."
        $envHash = @{}
        foreach ($prop in $Addon.ensureEnv.PSObject.Properties) {
            $envHash[$prop.Name] = $prop.Value
        }
        Ensure-SettingsEnv -EnvVars $envHash
    }

    # Run postinstall script if defined
    if ($Addon.Scripts -and $Addon.Scripts.postinstall) {
        Write-Info "Uruchamiam postinstall script..."
        # Ustaw zmienne srodowiskowe dla postinstall skryptu
        $env:ADDON_DIR = $Addon.Path
        # M2: podstaw OBA tokeny (.Replace = literalnie, bez metaznakow regex w sciezce).
        # Bashowe postinstalle uzywaja $ADDON_DIR; bez tego "bash $ADDON_DIR/install.sh"
        # szlo do iex jako pusta zmienna PS -> "bash /install.sh".
        $env:CLAUDE_TARGET_BASE = (Join-Path $TargetBase ".claude")   # M24: wspolny korzen dla postinstalli
        $postinstallCmd = $Addon.Scripts.postinstall.Replace("%ADDON_DIR%", $Addon.Path).Replace('$ADDON_DIR', $Addon.Path)
        try {
            $global:LASTEXITCODE = 0
            Invoke-Expression $postinstallCmd
            # M1: native exit!=0 NIE rzuca wyjatku -> sprawdz $LASTEXITCODE jawnie
            if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
                Write-Err "Postinstall ZWROCIL BLAD (exit $LASTEXITCODE) — addon moze nie dzialac"
            } else {
                Write-OK "Postinstall wykonany"
            }
        } catch {
            Write-Warn "Blad postinstall: $_"
        } finally {
            $env:ADDON_DIR = $null  # Posprzataj
            $env:CLAUDE_TARGET_BASE = $null
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
    # M1/M29: przechwyc wynik (propagacja do kodu wyjscia + brak wycieku 'True' na stdout)
    $ok = Install-Addon -Addon $selected
    if ($ok) { exit 0 } else { exit 1 }
}

# All mode
if ($All) {
    Write-Host "  Instaluje wszystkie dodatki ($($addons.Count))..." -ForegroundColor White
    $failed = 0
    foreach ($a in $addons) {
        if (-not (Install-Addon -Addon $a)) { $failed++ }
    }
    Write-Host ""
    if ($failed -eq 0) {
        Write-OK "Wszystkie dodatki zainstalowane!"; exit 0
    } else {
        Write-Err "$failed addon(ow) zakonczylo z bledami — patrz wyzej"; exit 1
    }
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

$failed = 0
if ($choice -match "^[Aa]") {
    foreach ($a in $addons) {
        if (-not (Install-Addon -Addon $a)) { $failed++ }
    }
} else {
    # M16: filtruj tokeny do samych cyfr PRZED castem (pod EAP=Stop "1," / "1;2" rzucaly terminating error)
    $indices = @($choice -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 })
    if ($indices.Count -eq 0) { Write-Warn "Brak poprawnych numerow w '$choice'" }
    foreach ($i in $indices) {
        if ($i -ge 0 -and $i -lt $addons.Count) {
            if (-not (Install-Addon -Addon $addons[$i])) { $failed++ }
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
# M1/M29: kod wyjscia odzwierciedla porazki (tryb interaktywny)
if ($failed -gt 0) { exit 1 } else { exit 0 }
