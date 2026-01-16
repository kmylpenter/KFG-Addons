# Analiza historycznych sesji Claude Code
# Przechodzi przez wszystkie .jsonl i sumuje tokeny z kazdej wiadomosci
# v7.0: Simplified folder prefix mapping (no pathPatterns)
# v6.0: Custom DeviceId from pathPatterns in kfg-stats config
# v5.0: Inkrementalne przetwarzanie - tylko nowe/zmienione pliki

param(
    [switch]$Verbose,
    [switch]$Force,              # Wymus pelna analize (ignoruj cache)
    [string]$UserFilter = "",    # Filter by user (e.g., "Kmyl")
    [string]$OutputFile = ""     # Pusty = domyslny totals-history.json
)

$projectsDir = "$env:USERPROFILE\.claude\projects"
$historyFile = if ($OutputFile) { $OutputFile } else { "$env:USERPROFILE\.claude\totals-history.json" }
$configPath = "$env:USERPROFILE\.config\kfg-stats\users.json"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        ANALIZA HISTORYCZNYCH SESJI CLAUDE CODE v7.0        " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
if ($UserFilter) {
    Write-Host "        Filtr uzytkownika: $UserFilter" -ForegroundColor Yellow
}
Write-Host ""

# === LOAD CONFIG ===
$folderMapping = @{}
$defaultUser = $null

if (Test-Path $configPath) {
    try {
        $json = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($json.folderMapping) {
            foreach ($prop in $json.folderMapping.PSObject.Properties) {
                $folderMapping[$prop.Name] = $prop.Value
            }
        }
        $defaultUser = $json.defaultUser
        Write-Host "  Config: $($folderMapping.Count) folder mappings loaded" -ForegroundColor DarkGray
    } catch {
        Write-Host "  Config: blad wczytywania" -ForegroundColor DarkYellow
    }
}

# Extract meaningful prefix from folder name (same logic as kfg-settings)
function Get-FolderPrefix {
    param([string]$FolderName)

    # android--data-data-com-termux-... → android--data-data-com-termux
    if ($FolderName -match '^(android--data-data-com-termux)') {
        return $Matches[1]
    }

    # C--Users-USERNAME-... → C--Users-USERNAME
    if ($FolderName -match '^([A-Za-z])--Users-([^-]+)') {
        return "$($Matches[1])--Users-$($Matches[2])"
    }

    # D--Projekty-XXX-YYY-projectname → D--Projekty-XXX-YYY (main projects folder)
    # Take max 2 uppercase segments after "Projekty" (e.g., DELL-KG or StriX)
    if ($FolderName -match '^([A-Z])--Projekty-') {
        $parts = $FolderName -split '-'
        $prefix = @($parts[0], '', 'Projekty')
        $segmentsAdded = 0
        $maxSegments = 2

        for ($i = 3; $i -lt $parts.Count -and $segmentsAdded -lt $maxSegments; $i++) {
            $segment = $parts[$i]
            if ($segment -and $segment[0] -cmatch '[a-z]') {
                break
            }
            if ($segment) {
                $prefix += $segment
                $segmentsAdded++
            }
        }
        return $prefix -join '-'
    }

    return $null
}

# Get user for folder using folderMapping
function Get-UserFromFolder {
    param([string]$FolderName)

    $prefix = Get-FolderPrefix $FolderName
    if ($prefix -and $folderMapping.ContainsKey($prefix)) {
        return @{ user = $folderMapping[$prefix]; prefix = $prefix }
    }

    # Fallback to default user
    return @{ user = $defaultUser; prefix = $prefix }
}

# Sprawdz czy sesja pasuje do filtra
function Test-UserMatch {
    param([string]$User, [string]$Filter)
    if (-not $Filter) { return $true }
    return $User -eq $Filter
}

# Znajdz wszystkie foldery projektow
$allFolders = Get-ChildItem -Path $projectsDir -Directory -ErrorAction SilentlyContinue

if (-not $allFolders) {
    Write-Host "Brak folderow projektow w: $projectsDir" -ForegroundColor Red
    exit 1
}

Write-Host "Skanowanie $($allFolders.Count) folderow projektow..." -ForegroundColor Yellow
Write-Host ""

# v5.0: Laduj poprzednie wyniki (cache)
$cachedSessions = @{}
$cachedFileInfo = @{}
$previousResult = $null

if (-not $Force -and (Test-Path $historyFile)) {
    try {
        $previousResult = Get-Content $historyFile -Raw | ConvertFrom-Json
        if ($previousResult.sessions) {
            foreach ($prop in $previousResult.sessions.PSObject.Properties) {
                $cachedSessions[$prop.Name] = $prop.Value
            }
        }
        if ($previousResult.file_cache) {
            foreach ($prop in $previousResult.file_cache.PSObject.Properties) {
                $cachedFileInfo[$prop.Name] = $prop.Value
            }
        }
        Write-Host "  Cache: $($cachedSessions.Count) sesji z poprzedniej analizy" -ForegroundColor DarkGray
    } catch {
        Write-Host "  Cache: blad wczytywania, pelna analiza" -ForegroundColor DarkYellow
    }
}

$globalStats = @{
    total_input_tokens = 0
    total_output_tokens = 0
    total_cache_read = 0
    total_cache_write = 0
    total_agent_savings = 0
    sessions_count = 0
    messages_count = 0
    user_prompts_count = 0
    chars_user_total = 0
    chars_ai_total = 0
    files_processed = 0
    files_skipped = 0
    cache_hits = 0
    cache_misses = 0
}

$sessionsData = @{}
$newFileCache = @{}

foreach ($project in $allFolders) {
    # Get user for this folder
    $userInfo = Get-UserFromFolder $project.Name
    $folderUser = $userInfo.user
    $folderPrefix = $userInfo.prefix

    # Check user filter early (skip whole folder if doesn't match)
    if ($UserFilter -and $folderUser -ne $UserFilter) {
        continue
    }

    # Znajdz pliki sesji (UUID.jsonl, nie agent-*)
    $sessionFiles = Get-ChildItem -Path $project.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.jsonl$" }

    if ($Verbose) {
        Write-Host "  $($project.Name): $($sessionFiles.Count) sesji -> $folderUser" -ForegroundColor Gray
    }

    foreach ($file in $sessionFiles) {
        $sessionId = $file.BaseName

        # Pomin duplikaty
        if ($sessionsData.ContainsKey($sessionId)) { continue }

        # v5.0: Sprawdz czy plik sie zmienil (cache hit)
        $fileKey = $file.FullName
        $fileMtime = $file.LastWriteTime.Ticks
        $fileSize = $file.Length

        $newFileCache[$fileKey] = @{ mtime = $fileMtime; size = $fileSize }

        $cachedInfo = $cachedFileInfo[$fileKey]
        if ($cachedInfo -and $cachedInfo.mtime -eq $fileMtime -and $cachedInfo.size -eq $fileSize) {
            if ($cachedSessions.ContainsKey($sessionId)) {
                $cached = $cachedSessions[$sessionId]

                # Update folder_prefix and user if needed
                $cached.folder_prefix = $folderPrefix
                $cached.user = $folderUser

                $sessionsData[$sessionId] = $cached
                $globalStats.total_input_tokens += $cached.tokens_in
                $globalStats.total_output_tokens += $cached.tokens_out
                $globalStats.total_cache_read += $cached.cache_read
                $globalStats.total_cache_write += $cached.cache_write
                $globalStats.total_agent_savings += $cached.agent_savings
                $globalStats.messages_count += $cached.messages
                $globalStats.user_prompts_count += $cached.user_prompts
                $globalStats.chars_user_total += if ($cached.chars_user) { $cached.chars_user } else { 0 }
                $globalStats.chars_ai_total += if ($cached.chars_ai) { $cached.chars_ai } else { 0 }
                $globalStats.sessions_count++
                $globalStats.cache_hits++
                $globalStats.files_processed++
                continue
            }
        }

        # Cache miss - przetworz plik
        $globalStats.cache_misses++

        $sessionTokensIn = 0
        $sessionTokensOut = 0
        $sessionCacheRead = 0
        $sessionCacheWrite = 0
        $sessionAgentSavings = 0
        $sessionMessages = 0
        $sessionUserPrompts = 0
        $sessionCharsUser = 0
        $sessionCharsAi = 0
        $sessionStart = $null
        $sessionEnd = $null

        try {
            $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue

            foreach ($line in $lines) {
                if (-not $line.Trim()) { continue }

                try {
                    $msg = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if (-not $msg) { continue }

                    # Timestamp
                    if ($msg.timestamp) {
                        if (-not $sessionStart) { $sessionStart = $msg.timestamp }
                        $sessionEnd = $msg.timestamp
                    }

                    # User prompts
                    if ($msg.type -eq "user" -and -not $msg.isMeta -and -not $msg.isSidechain) {
                        $content = if ($msg.message -and $msg.message.content) { $msg.message.content } else { "" }
                        if ($content -is [array]) {
                            $textParts = @()
                            foreach ($c in $content) {
                                if ($c.type -eq "text" -and $c.text) { $textParts += $c.text }
                            }
                            $content = $textParts -join ""
                        }
                        $isCommand = $content -match "^<command-name>" -or $content -match "^<local-command"
                        $isWarmup = $content.Trim() -eq "Warmup"
                        if ($content -and -not $isCommand -and -not $isWarmup) {
                            $sessionUserPrompts++
                            $sessionCharsUser += $content.Length
                        }
                    }

                    # AI chars
                    if ($msg.type -eq "assistant" -and $msg.message -and $msg.message.content) {
                        $aiContent = $msg.message.content
                        if ($aiContent -is [string]) {
                            $sessionCharsAi += $aiContent.Length
                        } elseif ($aiContent -is [array]) {
                            foreach ($c in $aiContent) {
                                if ($c.type -eq "text" -and $c.text) {
                                    $sessionCharsAi += $c.text.Length
                                }
                                if ($c.type -eq "tool_use" -and $c.input) {
                                    if ($c.input.content) { $sessionCharsAi += $c.input.content.Length }
                                    if ($c.input.new_string) { $sessionCharsAi += $c.input.new_string.Length }
                                }
                            }
                        }
                    }

                    # Usage
                    if ($msg.message -and $msg.message.usage) {
                        $usage = $msg.message.usage
                        $sessionTokensIn += if ($usage.input_tokens) { $usage.input_tokens } else { 0 }
                        $sessionTokensOut += if ($usage.output_tokens) { $usage.output_tokens } else { 0 }
                        $sessionCacheRead += if ($usage.cache_read_input_tokens) { $usage.cache_read_input_tokens } else { 0 }
                        $sessionCacheWrite += if ($usage.cache_creation_input_tokens) { $usage.cache_creation_input_tokens } else { 0 }
                        $sessionMessages++
                    }

                    # Agent savings
                    if ($msg.toolUseResult -and $msg.toolUseResult.totalTokens) {
                        $tur = $msg.toolUseResult
                        $agentTotalTokens = [long]$tur.totalTokens
                        $summaryTokens = 0
                        if ($tur.content -and $tur.content.Count -gt 0) {
                            foreach ($c in $tur.content) {
                                if ($c.text) { $summaryTokens += [math]::Ceiling($c.text.Length / 4) }
                            }
                        }
                        $contribution = $agentTotalTokens - $summaryTokens
                        if ($contribution -gt 0) { $sessionAgentSavings += $contribution }
                    }

                } catch { }
            }

            # Oblicz czas sesji
            $durationMs = 0
            if ($sessionStart -and $sessionEnd) {
                try {
                    $start = [DateTime]::Parse($sessionStart)
                    $end = [DateTime]::Parse($sessionEnd)
                    $durationMs = ($end - $start).TotalMilliseconds
                } catch { }
            }

            # Oszacuj koszt (Opus 4.5 pricing)
            $costInput = ($sessionTokensIn / 1000000) * 15
            $costOutput = ($sessionTokensOut / 1000000) * 75
            $costCacheRead = ($sessionCacheRead / 1000000) * 1.5
            $costCacheWrite = ($sessionCacheWrite / 1000000) * 18.75
            $sessionCost = $costInput + $costOutput + $costCacheRead + $costCacheWrite

            # Zapisz sesje
            if ($sessionMessages -gt 0) {
                $sessionTokensTotal = $sessionTokensIn + $sessionTokensOut + $sessionCacheRead + $sessionCacheWrite
                $sessionsData[$sessionId] = @{
                    cost = [math]::Round($sessionCost, 4)
                    duration_ms = [int64]$durationMs
                    tokens_main = $sessionTokensIn + $sessionTokensOut
                    tokens_total = $sessionTokensTotal
                    tokens_in = $sessionTokensIn
                    tokens_out = $sessionTokensOut
                    cache_read = $sessionCacheRead
                    cache_write = $sessionCacheWrite
                    agent_savings = $sessionAgentSavings
                    messages = $sessionMessages
                    user_prompts = $sessionUserPrompts
                    chars_user = $sessionCharsUser
                    chars_ai = $sessionCharsAi
                    folder_prefix = $folderPrefix
                    user = $folderUser
                    last_update = (Get-Date -Format "yyyy-MM-dd HH:mm")
                    source = "history"
                }

                $globalStats.total_input_tokens += $sessionTokensIn
                $globalStats.total_output_tokens += $sessionTokensOut
                $globalStats.total_cache_read += $sessionCacheRead
                $globalStats.total_cache_write += $sessionCacheWrite
                $globalStats.total_agent_savings += $sessionAgentSavings
                $globalStats.messages_count += $sessionMessages
                $globalStats.user_prompts_count += $sessionUserPrompts
                $globalStats.chars_user_total += $sessionCharsUser
                $globalStats.chars_ai_total += $sessionCharsAi
                $globalStats.sessions_count++
            }

        } catch {
            if ($Verbose) { Write-Host "    Blad: $($file.Name)" -ForegroundColor Red }
        }

        $globalStats.files_processed++

        if ($globalStats.files_processed % 20 -eq 0) {
            Write-Host "`r  Przetworzono: $($globalStats.files_processed) plikow, $($globalStats.sessions_count) sesji..." -NoNewline -ForegroundColor Gray
        }
    }
}

Write-Host "`r                                                              " -NoNewline
Write-Host ""

# Oblicz totals
$totalCost = 0.0
$totalDurMs = 0
$totalTokMain = 0
$totalTokTotal = 0
$totalAgentSavings = 0

foreach ($sess in $sessionsData.Values) {
    $totalCost += $sess.cost
    $totalDurMs += $sess.duration_ms
    $totalTokMain += $sess.tokens_main
    $totalTokTotal += $sess.tokens_total
    $totalAgentSavings += $sess.agent_savings
}

# Zapisz do pliku
$result = @{
    last_analyzed = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    analysis_stats = @{
        files_processed = $globalStats.files_processed
        files_skipped = $globalStats.files_skipped
        sessions_found = $globalStats.sessions_count
        messages_total = $globalStats.messages_count
        user_prompts_total = $globalStats.user_prompts_count
        chars_user_total = $globalStats.chars_user_total
        chars_ai_total = $globalStats.chars_ai_total
        cache_hits = $globalStats.cache_hits
        cache_misses = $globalStats.cache_misses
    }
    file_cache = $newFileCache
    total_cost = [math]::Round($totalCost, 2)
    total_duration_ms = $totalDurMs
    total_tokens_main = $totalTokMain
    total_tokens_total = $totalTokTotal
    total_agent_savings = $totalAgentSavings
    total_user_prompts = $globalStats.user_prompts_count
    total_chars_user = $globalStats.chars_user_total
    total_chars_ai = $globalStats.chars_ai_total
    compacts = 0
    sessions = $sessionsData
}

$result | ConvertTo-Json -Depth 5 -Compress:$false | Out-File -FilePath $historyFile -Encoding UTF8

# Formatuj wyniki
$totalHours = [math]::Round($totalDurMs / 3600000, 1)
$totalDays = [math]::Floor($totalHours / 24)
$totalTokMainM = [math]::Round($totalTokMain / 1000000, 2)
$totalTokTotalM = [math]::Round($totalTokTotal / 1000000, 2)
$totalAgentSavingsM = [math]::Round($totalAgentSavings / 1000000, 2)

Write-Host "============================================================" -ForegroundColor Green
Write-Host "                      WYNIKI ANALIZY                        " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Plikow przetworzonych:  $($globalStats.files_processed)" -ForegroundColor White
if ($UserFilter) {
    Write-Host "  Filtr uzytkownika:      $UserFilter" -ForegroundColor Yellow
}
if ($globalStats.cache_hits -gt 0 -or $globalStats.cache_misses -gt 0) {
    Write-Host "  Cache hits:             $($globalStats.cache_hits) (pominieto)" -ForegroundColor DarkGreen
    Write-Host "  Cache misses:           $($globalStats.cache_misses) (przetworzone)" -ForegroundColor DarkYellow
}
Write-Host "  Unikalnych sesji:       $($globalStats.sessions_count)" -ForegroundColor White
Write-Host "  Wiadomosci:             $($globalStats.messages_count)" -ForegroundColor White
Write-Host ""
Write-Host "------------------------------------------------------------" -ForegroundColor Green
Write-Host ""
Write-Host "  Czas laczny:            $totalHours godzin (~${totalDays} dni)" -ForegroundColor Yellow
Write-Host "  Tokeny (main):          ${totalTokMainM}M (input+output)" -ForegroundColor Cyan
Write-Host "  Tokeny (total):         ${totalTokTotalM}M (+ cache)" -ForegroundColor Cyan
Write-Host "  Agent savings:          ${totalAgentSavingsM}M (delegowanie)" -ForegroundColor Blue
Write-Host "  Koszt API:              `$$([math]::Round($totalCost, 2))" -ForegroundColor Magenta
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Zapisano do: $historyFile" -ForegroundColor Gray
Write-Host ""
