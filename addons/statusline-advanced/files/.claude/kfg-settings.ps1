# KFG Settings - Interactive Menu
# v2.0 - Simplified folder prefix mapping (no pathPatterns)

$ErrorActionPreference = 'SilentlyContinue'
$configPath = "$env:USERPROFILE\.config\kfg-stats\users.json"
$projectsDir = "$env:USERPROFILE\.claude\projects"

# Build prefix cache from all folders (finds repeating prefixes)
$script:prefixCache = $null

function Build-PrefixCache {
    if ($script:prefixCache) { return }
    # Case-sensitive hashtable (DELL != Dell)
    $script:prefixCache = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)

    $allFolders = @()
    if (Test-Path $projectsDir) {
        $allFolders = Get-ChildItem -Path $projectsDir -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    }

    foreach ($folder in $allFolders) {
        $parts = $folder -split '-'
        # Only index first 6 segments (max 3 after D--Projekty-)
        $maxLen = [Math]::Min($parts.Count, 4)
        for ($len = 3; $len -le $maxLen; $len++) {
            $prefix = ($parts[0..($len-1)]) -join '-'
            if (-not $script:prefixCache.ContainsKey($prefix)) {
                $script:prefixCache[$prefix] = 0
            }
            $script:prefixCache[$prefix]++
        }
    }
}

# Extract meaningful prefix from folder name
# Returns shortest prefix that groups multiple folders together
function Get-FolderPrefix {
    param([string]$FolderName)

    Build-PrefixCache

    # android--data-data-com-termux-... → android--data-data-com-termux
    if ($FolderName -match '^(android--data-data-com-termux)') {
        return $Matches[1]
    }

    # C--Users-USERNAME-... → C--Users-USERNAME
    if ($FolderName -match '^([A-Za-z])--Users-([^-]+)') {
        return "$($Matches[1])--Users-$($Matches[2])"
    }

    # D--Projekty-... → find shortest repeating prefix
    if ($FolderName -match '^([A-Za-z])--Projekty-') {
        $parts = $FolderName -split '-'
        # Start from X--Projekty-FIRST (4 parts), max 3 segments after Projekty (=6 total)
        $maxLen = [Math]::Min($parts.Count, 4)
        for ($len = 4; $len -le $maxLen; $len++) {
            $prefix = ($parts[0..($len-1)]) -join '-'
            $count = $script:prefixCache[$prefix]
            # If this prefix groups multiple folders, use it
            # If extending further would make it unique (count=1), stop here
            if ($count -gt 1) {
                $nextPrefix = if ($len -lt $parts.Count) { ($parts[0..$len]) -join '-' } else { $null }
                $nextCount = if ($nextPrefix) { $script:prefixCache[$nextPrefix] } else { 0 }
                if ($nextCount -le 1) {
                    return $prefix
                }
            }
        }
        # Fallback: use first 4 segments (X--Projekty-FIRST)
        if ($parts.Count -ge 4) {
            return ($parts[0..3]) -join '-'
        }
    }

    # C-- (root) - skip these
    if ($FolderName -match '^[A-Z]--$') {
        return $null
    }

    return $null
}

# Discover all unique prefixes from projects folder
function Get-AllPrefixes {
    $prefixes = @{}

    if (-not (Test-Path $projectsDir)) {
        return @{}
    }

    Get-ChildItem -Path $projectsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $prefix = Get-FolderPrefix $_.Name
        if ($prefix) {
            if (-not $prefixes.ContainsKey($prefix)) {
                $prefixes[$prefix] = 0
            }
            $prefixes[$prefix]++
        }
    }

    return $prefixes
}

# Get human-readable name for prefix
function Get-PrefixDisplayName {
    param([string]$Prefix)

    if ($Prefix -eq 'android--data-data-com-termux') {
        return "Android (Termux)"
    }
    if ($Prefix -match '^([A-Z])--Users-(.+)$') {
        return "$($Matches[1]):\Users\$($Matches[2])"
    }
    if ($Prefix -match '^([A-Z])--Projekty-(.+)$') {
        $rest = $Matches[2] -replace '-', ' '
        return "$($Matches[1]):\Projekty $rest"
    }
    return $Prefix
}

function Get-KfgStatsPath {
    $statsPath = "$env:USERPROFILE\.claude-history\stats"
    if (-not (Test-Path $statsPath)) {
        New-Item -ItemType Directory -Path $statsPath -Force | Out-Null
    }
    return $statsPath
}

function Load-Config {
    if (-not (Test-Path $configPath)) {
        $configDir = Split-Path $configPath -Parent
        if (-not (Test-Path $configDir)) {
            New-Item -ItemType Directory -Path $configDir -Force | Out-Null
        }
        $default = @{
            defaultUser = $env:USERNAME
            users = @{ $env:USERNAME = @{ devices = @() } }
            folderMapping = @{}
            statsPath = Get-KfgStatsPath
        }
        $default | ConvertTo-Json -Depth 5 | Out-File $configPath -Encoding UTF8
        return $default
    }

    $json = Get-Content $configPath -Raw | ConvertFrom-Json
    $config = @{
        defaultUser = $json.defaultUser
        statsPath = if ($json.statsPath) { $json.statsPath } else { Get-KfgStatsPath }
        users = @{}
        folderMapping = @{}
    }

    # Load users
    if ($json.users) {
        foreach ($prop in $json.users.PSObject.Properties) {
            $config.users[$prop.Name] = @{ devices = @($prop.Value.devices) }
        }
    }

    # Load folderMapping (new simplified format)
    if ($json.folderMapping) {
        foreach ($prop in $json.folderMapping.PSObject.Properties) {
            $config.folderMapping[$prop.Name] = $prop.Value
        }
    }

    return $config
}

function Save-Config {
    param($Config)
    $Config | ConvertTo-Json -Depth 5 | Out-File $configPath -Encoding UTF8
}

function Show-Menu {
    param([string]$Title, [array]$Options, [int]$Selected = 0)
    $cursorTop = [Console]::CursorTop
    while ($true) {
        [Console]::SetCursorPosition(0, $cursorTop)
        Write-Host ""
        Write-Host "  $Title" -ForegroundColor Cyan
        Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
        for ($i = 0; $i -lt $Options.Count; $i++) {
            if ($i -eq $Selected) {
                Write-Host "  > " -NoNewline -ForegroundColor Yellow
                Write-Host "$($Options[$i])" -ForegroundColor White
            } else {
                Write-Host "    $($Options[$i])" -ForegroundColor Gray
            }
        }
        Write-Host ""
        Write-Host "  [Up/Down] Navigate  [Enter] Select  [Esc] Back" -ForegroundColor DarkGray
        Write-Host "                                                    "
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            38 { $Selected = if ($Selected -gt 0) { $Selected - 1 } else { $Options.Count - 1 } }
            40 { $Selected = if ($Selected -lt $Options.Count - 1) { $Selected + 1 } else { 0 } }
            13 { return $Selected }
            27 { return -1 }
        }
    }
}

function Read-Input {
    param([string]$Prompt, [string]$Default = "")
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor Yellow -NoNewline
    if ($Default) { Write-Host " [$Default]" -ForegroundColor DarkGray -NoNewline }
    Write-Host ": " -NoNewline
    $val = Read-Host
    if (-not $val -and $Default) { return $Default }
    return $val
}

function Show-MainMenu {
    param($Config)

    # Count unmapped prefixes
    $allPrefixes = Get-AllPrefixes
    $unmappedCount = 0
    foreach ($prefix in $allPrefixes.Keys) {
        if (-not $Config.folderMapping.ContainsKey($prefix)) {
            $unmappedCount++
        }
    }

    $mappingStatus = if ($unmappedCount -gt 0) { "($unmappedCount unmapped)" } else { "(all mapped)" }

    $options = @(
        "Folder mapping $mappingStatus"
        "Users ($($Config.users.Count))"
        "Default: $($Config.defaultUser)"
        "Show statistics"
        "Exit"
    )
    return Show-Menu "KFG Settings v2.0" $options
}

function Show-FolderMappingMenu {
    param($Config)

    $allPrefixes = Get-AllPrefixes
    $options = @()
    $prefixList = @()

    # Sort: unmapped first, then mapped
    $sorted = $allPrefixes.Keys | Sort-Object {
        $mapped = $Config.folderMapping.ContainsKey($_)
        if ($mapped) { "1_$_" } else { "0_$_" }
    }

    foreach ($prefix in $sorted) {
        $count = $allPrefixes[$prefix]
        $displayName = Get-PrefixDisplayName $prefix
        $user = $Config.folderMapping[$prefix]

        if ($user) {
            $options += "$displayName -> $user ($count)"
        } else {
            $options += "$displayName [?] ($count)"
        }
        $prefixList += $prefix
    }

    $options += "[Auto-assign to default user]"
    $options += "<< Back"

    $choice = Show-Menu "Folder Mapping" $options

    if ($choice -eq -1 -or $choice -eq $options.Count - 1) {
        return $null  # Back
    }

    if ($choice -eq $options.Count - 2) {
        return "AUTO_ASSIGN"
    }

    if ($choice -lt $prefixList.Count) {
        return $prefixList[$choice]
    }

    return $null
}

function Show-AssignUserMenu {
    param($Config, [string]$Prefix)

    $displayName = Get-PrefixDisplayName $Prefix
    $options = @($Config.users.Keys | Sort-Object)
    $options += "[Remove mapping]"
    $options += "<< Cancel"

    $choice = Show-Menu "Assign: $displayName" $options

    if ($choice -eq -1 -or $choice -eq $options.Count - 1) {
        return $null  # Cancel
    }

    if ($choice -eq $options.Count - 2) {
        return "REMOVE"
    }

    return $options[$choice]
}

function Show-UsersMenu {
    param($Config)
    $options = @()
    foreach ($user in $Config.users.Keys | Sort-Object) {
        $mark = if ($user -eq $Config.defaultUser) { " *" } else { "" }
        $options += "$user$mark"
    }
    $options += "[+] Add user"
    $options += "<< Back"
    return Show-Menu "Users" $options
}

function Show-UserDetailMenu {
    param($Config, [string]$UserName)

    # Count folders mapped to this user
    $folderCount = 0
    foreach ($prefix in $Config.folderMapping.Keys) {
        if ($Config.folderMapping[$prefix] -eq $UserName) {
            $folderCount++
        }
    }

    $options = @(
        "Mapped folders: $folderCount"
    )
    if ($UserName -ne $Config.defaultUser) {
        $options += "Set as default"
        $options += "Delete user"
    }
    $options += "<< Back"
    return Show-Menu "User: $UserName" $options
}

function Show-Stats {
    param($Config)
    Clear-Host
    Write-Host ""
    Write-Host "  STATISTICS" -ForegroundColor Cyan
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray

    # Aggregate stats per user from analyze results
    $totalsFile = "$env:USERPROFILE\.claude\totals-history.json"
    $userStats = @{}

    foreach ($user in $Config.users.Keys) {
        $userStats[$user] = @{ cost = 0; duration_ms = 0; sessions = 0 }
    }

    if (Test-Path $totalsFile) {
        try {
            $data = Get-Content $totalsFile -Raw | ConvertFrom-Json
            if ($data.sessions) {
                foreach ($prop in $data.sessions.PSObject.Properties) {
                    $session = $prop.Value
                    $user = $null

                    # Find user by folder mapping
                    if ($session.folder_prefix) {
                        $user = $Config.folderMapping[$session.folder_prefix]
                    }

                    if (-not $user) { $user = $Config.defaultUser }

                    if ($userStats.ContainsKey($user)) {
                        $userStats[$user].cost += $session.cost
                        $userStats[$user].duration_ms += $session.duration_ms
                        $userStats[$user].sessions++
                    }
                }
            }
        } catch {
            Write-Host "  Error loading stats" -ForegroundColor Red
        }
    }

    foreach ($user in $Config.users.Keys | Sort-Object) {
        $stats = $userStats[$user]
        $days = [math]::Floor($stats.duration_ms / 86400000)
        $hours = [math]::Floor(($stats.duration_ms % 86400000) / 3600000)
        $costStr = if ($stats.cost -ge 1000) { "`$" + [math]::Round($stats.cost/1000, 1) + "k" } else { "`$" + [math]::Round($stats.cost, 0) }
        $mark = if ($user -eq $Config.defaultUser) { " (default)" } else { "" }

        Write-Host ""
        Write-Host "  $user$mark" -ForegroundColor Yellow
        Write-Host "    Time:     ${days}d ${hours}h" -ForegroundColor Gray
        Write-Host "    Cost:     $costStr" -ForegroundColor Magenta
        Write-Host "    Sessions: $($stats.sessions)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "  Press any key..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# === MAIN ===
Clear-Host
$config = Load-Config

while ($true) {
    Clear-Host
    $choice = Show-MainMenu $config

    switch ($choice) {
        0 {
            # Folder mapping
            while ($true) {
                Clear-Host
                $prefix = Show-FolderMappingMenu $config

                if (-not $prefix) { break }

                if ($prefix -eq "AUTO_ASSIGN") {
                    # Auto-assign all unmapped to default user
                    $allPrefixes = Get-AllPrefixes
                    $assigned = 0
                    foreach ($p in $allPrefixes.Keys) {
                        if (-not $config.folderMapping.ContainsKey($p)) {
                            $config.folderMapping[$p] = $config.defaultUser
                            $assigned++
                        }
                    }
                    Save-Config $config
                    Write-Host "  Assigned $assigned folders to $($config.defaultUser)" -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                    continue
                }

                Clear-Host
                $user = Show-AssignUserMenu $config $prefix

                if ($user -eq "REMOVE") {
                    $config.folderMapping.Remove($prefix)
                    Save-Config $config
                    Write-Host "  Removed mapping" -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                }
                elseif ($user) {
                    $config.folderMapping[$prefix] = $user
                    Save-Config $config
                    Write-Host "  Assigned to $user" -ForegroundColor Green
                    Start-Sleep -Milliseconds 800
                }
            }
        }
        1 {
            # Users menu
            while ($true) {
                Clear-Host
                $userChoice = Show-UsersMenu $config
                $userNames = @($config.users.Keys | Sort-Object)

                if ($userChoice -eq -1 -or $userChoice -eq $userNames.Count + 1) { break }

                if ($userChoice -eq $userNames.Count) {
                    # Add user
                    $newUser = Read-Input "New user name"
                    if ($newUser -and -not $config.users.ContainsKey($newUser)) {
                        $config.users[$newUser] = @{ devices = @() }
                        Save-Config $config
                        Write-Host "  Added: $newUser" -ForegroundColor Green
                        Start-Sleep -Milliseconds 800
                    }
                }
                elseif ($userChoice -lt $userNames.Count) {
                    $selectedUser = $userNames[$userChoice]
                    while ($true) {
                        Clear-Host
                        $detailChoice = Show-UserDetailMenu $config $selectedUser

                        if ($detailChoice -eq -1) { break }

                        $isDefault = $selectedUser -eq $config.defaultUser
                        $backIdx = if ($isDefault) { 1 } else { 3 }

                        if ($detailChoice -eq $backIdx) { break }

                        if (-not $isDefault) {
                            if ($detailChoice -eq 1) {
                                # Set as default
                                $config.defaultUser = $selectedUser
                                Save-Config $config
                                Write-Host "  $selectedUser is now default" -ForegroundColor Green
                                Start-Sleep -Milliseconds 800
                            }
                            elseif ($detailChoice -eq 2) {
                                # Delete user
                                # Remove all folder mappings for this user
                                $toRemove = @()
                                foreach ($prefix in $config.folderMapping.Keys) {
                                    if ($config.folderMapping[$prefix] -eq $selectedUser) {
                                        $toRemove += $prefix
                                    }
                                }
                                foreach ($prefix in $toRemove) {
                                    $config.folderMapping.Remove($prefix)
                                }
                                $config.users.Remove($selectedUser)
                                Save-Config $config
                                Write-Host "  Deleted: $selectedUser" -ForegroundColor Green
                                Start-Sleep -Milliseconds 800
                                break
                            }
                        }
                    }
                }
            }
        }
        2 {
            # Default user
            Clear-Host
            $userNames = @($config.users.Keys | Sort-Object) + "<< Cancel"
            $defChoice = Show-Menu "Select default user" $userNames
            if ($defChoice -ge 0 -and $defChoice -lt $config.users.Count) {
                $config.defaultUser = @($config.users.Keys | Sort-Object)[$defChoice]
                Save-Config $config
            }
        }
        3 { Show-Stats $config }
        4 {
            Clear-Host
            Write-Host "KFG Settings closed" -ForegroundColor Gray
            return
        }
        -1 {
            Clear-Host
            Write-Host "KFG Settings closed" -ForegroundColor Gray
            return
        }
    }
}
