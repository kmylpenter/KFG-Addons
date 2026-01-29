# KFG Statusline Wrapper v5.6
# v5.6: PERF AUDIT - regex pre-filter, atomic writes, dirty-checking, .NET direct calls
# v5.5: INCREMENTAL PARSING - tylko nowe linie, cache per session
# Format 4x3 z poziomym parowaniem SESJA/TOTAL
#
# Rzad 1: Model/User | ctx%/compacts
# Rzad 2: czas/typing  | turns/AI_chars
# Rzad 3: tokens/prompts | cost/cost_t

$ErrorActionPreference = 'SilentlyContinue'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# === KOLORY ANSI ===
$esc = [char]27
$reset = "$esc[0m"
$c_red = "$esc[38;5;196m"
$c_green = "$esc[38;5;46m"
$c_lime = "$esc[38;5;154m"
$c_yellow = "$esc[38;5;226m"
$c_orange = "$esc[38;5;208m"
$c_orange_red = "$esc[38;5;202m"
$c_blue = "$esc[38;5;39m"
$c_purple = "$esc[38;5;171m"
$c_gray = "$esc[38;5;245m"

# === CACHE DIRECTORY ===
$cacheDir = "$env:USERPROFILE\.claude\statusline-cache"
if (-not [System.IO.Directory]::Exists($cacheDir)) {
    [System.IO.Directory]::CreateDirectory($cacheDir) | Out-Null
}

# === FUNKCJA: Load/Save Cache ===
function Get-TranscriptCache {
    param([string]$SessionId, [string]$TranscriptPath)
    $cacheFile = "$cacheDir\$SessionId.json"

    $default = @{
        last_offset = 0
        transcript_size = 0
        turns = 0
        agent_contribution = 0
        first_timestamp = $null
        last_timestamp = $null
        context_length = 0
        last_usage = $null
    }

    if (-not [System.IO.File]::Exists($cacheFile)) { return $default }

    try {
        $cache = [System.IO.File]::ReadAllText($cacheFile) | ConvertFrom-Json

        # Sprawdź czy transcript się nie zmniejszył (rewind/compact)
        $currentSize = 0
        if ($TranscriptPath -and [System.IO.File]::Exists($TranscriptPath)) {
            $currentSize = (Get-Item $TranscriptPath).Length
        }

        if ($currentSize -lt $cache.transcript_size) {
            # M12: Transcript rewind - reset offset but preserve accumulated counters
            return @{
                last_offset = 0
                transcript_size = 0
                turns = [int]$cache.turns
                agent_contribution = [long]$cache.agent_contribution
                first_timestamp = $cache.first_timestamp
                last_timestamp = $cache.last_timestamp
                context_length = [long]$cache.context_length
                last_usage = $cache.last_usage
            }
        }

        return @{
            last_offset = [long]$cache.last_offset
            transcript_size = [long]$cache.transcript_size
            turns = [int]$cache.turns
            agent_contribution = [long]$cache.agent_contribution
            first_timestamp = $cache.first_timestamp
            last_timestamp = $cache.last_timestamp
            context_length = [long]$cache.context_length
            last_usage = $cache.last_usage
        }
    } catch {
        return $default
    }
}

# M8: Atomic write - write to temp then rename (atomic on NTFS)
function Write-Atomic {
    param([string]$Path, [string]$Content)
    $tmp = "$Path.$PID.tmp"
    try {
        [System.IO.File]::WriteAllText($tmp, $Content, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($tmp, $Path, $true)  # overwrite=true (PS7+ / .NET 5+)
    } catch {
        # Fallback for PS5: Move doesn't support overwrite
        try {
            if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Delete($Path) }
            [System.IO.File]::Move($tmp, $Path)
        } catch {
            # Last resort: direct write
            try { [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false)) } catch {}
        }
    }
    # Cleanup temp on failure
    try { if ([System.IO.File]::Exists($tmp)) { [System.IO.File]::Delete($tmp) } } catch {}
}

function Save-TranscriptCache {
    param([string]$SessionId, [hashtable]$Cache)
    $cacheFile = "$cacheDir\$SessionId.json"
    try {
        $json = $Cache | ConvertTo-Json -Depth 5 -Compress
        Write-Atomic -Path $cacheFile -Content $json
    } catch {}
}

# === FUNKCJA: Inkrementalne parsowanie transcript ===
function Get-IncrementalTranscriptData {
    param([string]$TranscriptPath, [hashtable]$Cache)

    $result = @{
        turns = $Cache.turns
        agent_contribution = $Cache.agent_contribution
        first_timestamp = $Cache.first_timestamp
        last_timestamp = $Cache.last_timestamp
        context_length = $Cache.context_length
        last_usage = $Cache.last_usage
        new_offset = $Cache.last_offset
        new_size = $Cache.transcript_size
    }

    if (-not $TranscriptPath -or -not [System.IO.File]::Exists($TranscriptPath)) { return $result }

    try {
        $fileInfo = Get-Item $TranscriptPath
        $currentSize = $fileInfo.Length
        $result.new_size = $currentSize

        # Jeśli plik się nie zmienił - zwróć cached
        if ($currentSize -eq $Cache.transcript_size -and $Cache.last_offset -gt 0) {
            return $result
        }

        $fileStream = $null
        $reader = $null
        try {
            $fileStream = [System.IO.FileStream]::new(
                $TranscriptPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )

            # Seek do ostatniej pozycji
            if ($Cache.last_offset -gt 0 -and $Cache.last_offset -lt $currentSize) {
                $fileStream.Seek($Cache.last_offset, [System.IO.SeekOrigin]::Begin) | Out-Null
            }

            $reader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8)

            $mostRecentTimestamp = $null
            $mostRecentUsage = $null
            $linesProcessed = 0
            $maxLines = 5000  # C6: safeguard against huge re-parse
            $lastGoodOffset = $fileStream.Position  # M9: track last valid offset

            # Jeśli mamy cached usage, użyj go jako baseline
            if ($Cache.last_usage) {
                $mostRecentUsage = $Cache.last_usage
            }

            # C3+M6: Regex pre-filter + selective ConvertFrom-Json (10x fewer allocations)
            while ($null -ne ($line = $reader.ReadLine())) {
                if (-not $line.Trim()) { continue }
                $linesProcessed++
                if ($linesProcessed -gt $maxLines) { break }  # C6: line limit

                # Extract timestamp via regex (most lines have it, cheap extraction)
                if ($line -match '"timestamp"\s*:\s*"([^"]+)"') {
                    if (-not $result.first_timestamp) { $result.first_timestamp = $Matches[1] }
                    $result.last_timestamp = $Matches[1]
                }

                # Count user turns via regex (fast pre-check)
                if ($line -match '"type"\s*:\s*"user"') {
                    if ($line -notmatch '"isMeta"\s*:\s*true' -and $line -notmatch '"isSidechain"\s*:\s*true') {
                        $result.turns++
                    }
                }

                # Full parse ONLY for lines with usage or toolUseResult (expensive fields)
                $needFullParse = ($line -match '"usage"') -or ($line -match '"toolUseResult"')
                if ($needFullParse) {
                    try {
                        $entry = $line | ConvertFrom-Json
                    } catch {
                        # M9: Partial/truncated JSONL line - stop here
                        break
                    }

                    # Context length: najnowszy main chain entry z usage
                    if ($entry.message -and $entry.message.usage) {
                        $isSidechain = $entry.isSidechain -eq $true
                        $isError = $entry.isApiErrorMessage -eq $true
                        if (-not $isSidechain -and -not $isError) {
                            $mostRecentUsage = $entry.message.usage
                        }
                    }

                    # Agent contribution z toolUseResult (M13: prefer totalTokens)
                    if ($entry.toolUseResult) {
                        $tur = $entry.toolUseResult
                        $agentNewWork = 0
                        if ($tur.totalTokens) {
                            $agentNewWork = [long]$tur.totalTokens
                        } elseif ($tur.usage) {
                            $agentInput = if ($tur.usage.input_tokens) { [long]$tur.usage.input_tokens } else { 0 }
                            $agentCacheCreate = if ($tur.usage.cache_creation_input_tokens) { [long]$tur.usage.cache_creation_input_tokens } else { 0 }
                            $agentOutput = if ($tur.usage.output_tokens) { [long]$tur.usage.output_tokens } else { 0 }
                            $agentNewWork = $agentInput + $agentCacheCreate + $agentOutput
                        }

                        $summaryTokens = 0
                        if ($tur.content -and $tur.content.Count -gt 0) {
                            foreach ($c in $tur.content) {
                                if ($c.text) { $summaryTokens += [math]::Ceiling($c.text.Length / 4) }
                            }
                        }

                        $contribution = $agentNewWork - $summaryTokens
                        if ($contribution -gt 0) { $result.agent_contribution += $contribution }
                    }
                }

                # M9: Update last good offset after successful parse
                $reader.DiscardBufferedData()
                $lastGoodOffset = $fileStream.Position
            }

            # M9+M16: Use last good offset from successfully parsed lines
            $result.new_offset = $lastGoodOffset
            $result.last_usage = $mostRecentUsage

            # Oblicz context length z najnowszego usage
            if ($mostRecentUsage) {
                $inputTok = if ($mostRecentUsage.input_tokens) { [long]$mostRecentUsage.input_tokens } else { 0 }
                $cacheRead = if ($mostRecentUsage.cache_read_input_tokens) { [long]$mostRecentUsage.cache_read_input_tokens } else { 0 }
                $cacheCreate = if ($mostRecentUsage.cache_creation_input_tokens) { [long]$mostRecentUsage.cache_creation_input_tokens } else { 0 }
                $result.context_length = $inputTok + $cacheRead + $cacheCreate
            }
        } finally {
            if ($reader) { $reader.Dispose() }
            if ($fileStream) { $fileStream.Dispose() }
        }
    } catch {}

    return $result
}

# === FUNKCJA: Dynamiczny kolor dla ctx% ===
function Get-CtxColor {
    param([double]$Pct)
    if ($Pct -ge 85) { return $c_red }
    elseif ($Pct -ge 75) { return $c_orange_red }
    elseif ($Pct -ge 65) { return $c_orange }
    elseif ($Pct -ge 55) { return $c_yellow }
    elseif ($Pct -ge 40) { return $c_lime }
    else { return $c_green }
}

# === FUNKCJA: Formatowanie liczb ===
function Format-Number {
    param([long]$Num, [string]$Suffix = "")
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    # m20: Use Floor for M to avoid premature "1.0M" for 999.9k
    if ($Num -ge 1000000) { $v = [math]::Floor($Num / 100000) / 10; return "$v`M$Suffix" }
    elseif ($Num -ge 1000) { return ($Num / 1000).ToString("N1", $inv) + "k$Suffix" }
    else { return "$Num$Suffix" }
}

# === FUNKCJA: Formatowanie czasu ===
function Format-Time {
    param([int]$Seconds)
    $hours = [math]::Floor($Seconds / 3600)
    $mins = [math]::Floor(($Seconds % 3600) / 60)
    if ($hours -gt 0) { return "${hours}h${mins}m" }
    else { return "${mins}m" }
}

# === FUNKCJA: Formatowanie kosztu ===
function Format-Cost {
    param([double]$Cost)
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Cost -ge 1000) { return "`$" + ($Cost / 1000).ToString("N1", $inv) + "k" }
    else { return "`$" + $Cost.ToString("N2", $inv) }
}

# === CZYTAJ JSON ZE STDIN ===
$jsonInput = [Console]::In.ReadToEnd()
# M17+m4: Fix BOM pattern (Unicode FEFF not UTF-8 bytes) + skip if clean
if ($jsonInput.Length -gt 0 -and ($jsonInput[0] -eq "`0" -or $jsonInput[0] -eq [char]0xFEFF -or $jsonInput[0] -eq [char]0xFFFE)) {
    $jsonInput = $jsonInput -replace '\x00', '' -replace '^\xFEFF', '' -replace '^\xFFFE', ''
}
if (-not $jsonInput.Trim()) { exit 0 }

$data = $jsonInput | ConvertFrom-Json

# === PARSOWANIE DANYCH SESJI ===
# M10: Generate fallback ID from transcript path hash instead of "unknown"
# M11: Sanitize session ID to prevent path traversal
$rawSessionId = if ($data.session_id) { $data.session_id } else {
    if ($data.transcript_path) {
        "fallback-" + [System.IO.Path]::GetFileNameWithoutExtension($data.transcript_path)
    } else { "fallback-$PID" }
}
$sessionId = $rawSessionId -replace '[^a-zA-Z0-9_\-]', '_'
$sessionCost = 0.0
if ($data.cost -and $data.cost.total_cost_usd) { $sessionCost = [double]$data.cost.total_cost_usd }

# Model name (skrocona wersja np. O4.5, S3.5, H3)
$modelName = "?"
$rawModel = $null

if ($data.model) {
    if ($data.model.id) { $rawModel = $data.model.id }
    elseif ($data.model.display_name) { $rawModel = $data.model.display_name }
}

if ($rawModel) {
    $version = ""
    if ($rawModel -match '(\d+)-(\d+)-\d{8}') {
        $version = "$($Matches[1]).$($Matches[2])"
    } elseif ($rawModel -match '(\d+)-\d{8}') {
        $version = $Matches[1]
    } elseif ($rawModel -match '(\d+\.\d+)') {
        $version = $Matches[1]
    }

    if ($rawModel -match 'opus') { $modelName = "O$version" }
    elseif ($rawModel -match 'sonnet') { $modelName = "S$version" }
    elseif ($rawModel -match 'haiku') { $modelName = "H$version" }
    else { $modelName = "C$version" }
}

# === INCREMENTAL TRANSCRIPT PARSING ===
$transcriptPath = $data.transcript_path
$cache = Get-TranscriptCache -SessionId $sessionId -TranscriptPath $transcriptPath
$transcriptData = Get-IncrementalTranscriptData -TranscriptPath $transcriptPath -Cache $cache

# M3: Zapisz cache TYLKO gdy dane się zmieniły (dirty-check)
$newCache = @{
    last_offset = $transcriptData.new_offset
    transcript_size = $transcriptData.new_size
    turns = $transcriptData.turns
    agent_contribution = $transcriptData.agent_contribution
    first_timestamp = $transcriptData.first_timestamp
    last_timestamp = $transcriptData.last_timestamp
    context_length = $transcriptData.context_length
    last_usage = $transcriptData.last_usage
}
$cacheDirty = ($newCache.last_offset -ne $cache.last_offset) -or `
              ($newCache.turns -ne $cache.turns) -or `
              ($newCache.agent_contribution -ne $cache.agent_contribution) -or `
              ($newCache.context_length -ne $cache.context_length)
if ($cacheDirty) {
    Save-TranscriptCache -SessionId $sessionId -Cache $newCache
}

# === OBLICZENIA ===
$contextLength = $transcriptData.context_length
$contextLimit = 160000
$contextPct = 0.0

if ($contextLimit -gt 0 -and $contextLength -gt 0) {
    $contextPct = [math]::Round(($contextLength / $contextLimit) * 100, 1)
}

$turns = $transcriptData.turns

# Session duration
$sessionDuration = 0
if ($transcriptData.first_timestamp -and $transcriptData.last_timestamp) {
    try {
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $firstTs = [DateTime]::Parse($transcriptData.first_timestamp, $inv)
        $lastTs = [DateTime]::Parse($transcriptData.last_timestamp, $inv)
        $sessionDuration = [int]($lastTs - $firstTs).TotalSeconds
    } catch {}
}

# M3: Zapis ctx% dla hookow - dirty-check
$ctxPctInt = [int][Math]::Round($contextPct)
$ctxCacheFile = "$env:TEMP\claude-context-pct-$sessionId.txt"
$prevCtxPct = -1
try { if ([System.IO.File]::Exists($ctxCacheFile)) { $prevCtxPct = [int][System.IO.File]::ReadAllText($ctxCacheFile).Trim() } } catch {}
if ($ctxPctInt -ne $prevCtxPct) {
    try { Write-Atomic -Path $ctxCacheFile -Content "$ctxPctInt" } catch {}
}

# === AGENT CONTRIBUTION / TOTAL TOKENS ===
# M14: Display current agent_contribution (not high-water mark)
# With M12 fix, counters survive rewind, so max_total tracking is no longer needed
$totalTokens = $transcriptData.agent_contribution

# === COMPACT COUNTER (per-session file) ===
$compactStateFile = "$cacheDir\compact-$sessionId.json"
$compactsCount = 0
$compactDirty = $false

try {
    if ([System.IO.File]::Exists($compactStateFile)) {
        $compactState = [System.IO.File]::ReadAllText($compactStateFile) | ConvertFrom-Json
        $compactsCount = [int]$compactState.count
        $prevCtxLength = [long]$compactState.last_context_length
        # Detect compaction: context dropped by >10% (removed $rewindDetected guard - C7 fix)
        if ($contextLength -gt 0 -and $prevCtxLength -gt 0) {
            if ($contextLength -lt ($prevCtxLength * 0.9)) {
                $compactsCount++
                $compactDirty = $true
            }
        }
        if ($contextLength -ne $prevCtxLength) { $compactDirty = $true }
    } else {
        $compactDirty = $true
    }
} catch { $compactDirty = $true }
if ($compactDirty) {
    $cJson = "{`"count`":$compactsCount,`"last_context_length`":$contextLength}"
    try { Write-Atomic -Path $compactStateFile -Content $cJson } catch {}
}

# === CROSS-DEVICE TOTALS (per-user stats) ===
$statsDir = "$env:USERPROFILE\.claude-history\stats"
$configPath = "$env:USERPROFILE\.config\kfg-stats\users.json"

$userName = $env:USERNAME
if ([System.IO.File]::Exists($configPath)) {
    try {
        $cfg = [System.IO.File]::ReadAllText($configPath) | ConvertFrom-Json
        if ($cfg.defaultUser) { $userName = $cfg.defaultUser }
    } catch {}
}

$totalCharsUser = 0; $totalCharsAi = 0; $totalUserPrompts = 0; $totalCost = 0.0
$userStatsFile = "$statsDir\user-$userName.json"
if ([System.IO.File]::Exists($userStatsFile)) {
    try {
        $userStats = [System.IO.File]::ReadAllText($userStatsFile) | ConvertFrom-Json
        $totalCharsUser = if ($userStats.chars_user) { [long]$userStats.chars_user } else { 0 }
        $totalCharsAi = if ($userStats.chars_ai) { [long]$userStats.chars_ai } else { 0 }
        $totalUserPrompts = if ($userStats.user_prompts) { [int]$userStats.user_prompts } else { 0 }
        $totalCost = if ($userStats.cost) { [double]$userStats.cost } else { 0 }
    } catch {}
}

$typingMinutes = if ($totalCharsUser -gt 0) { $totalCharsUser / 285 } else { 0 }
$typingHours = [math]::Floor($typingMinutes / 60)
$typingMins = [math]::Floor($typingMinutes % 60)
$typingTimeStr = if ($typingHours -gt 0) { "${typingHours}h${typingMins}m" } else { "${typingMins}m" }

# === FORMATOWANIE WARTOSCI ===
# m14: Cap display at 100% (context can technically exceed limit with cache tokens)
$ctxPctStr = if ($contextPct -gt 100) { "100%+" } else { "$contextPct%" }
$ctxColor = Get-CtxColor -Pct $contextPct

$sessionTimeStr = Format-Time -Seconds $sessionDuration
$turnsStr = "$turns"
$totalTokensStr = Format-Number -Num $totalTokens
$sessionCostStr = Format-Cost -Cost $sessionCost

$compactsStr = "$compactsCount"
$aiCharsStr = Format-Number -Num $totalCharsAi
$promptsStr = Format-Number -Num $totalUserPrompts
$totalCostStr = Format-Cost -Cost $totalCost

# === GENEROWANIE OUTPUTU 4x3 ===
$colW = 8

# m11: Names are historically swapped but callers use them consistently - adding alias comments
function Pad-Right([string]$text, [int]$width) {  # Actually LEFT-pads (right-aligns)
    if ($text.Length -ge $width) { return $text.Substring(0, $width) }
    return (" " * ($width - $text.Length)) + $text
}

function Pad-Left([string]$text, [int]$width) {  # Actually RIGHT-pads (left-aligns)
    if ($text.Length -ge $width) { return $text.Substring(0, $width) }
    return $text + (" " * ($width - $text.Length))
}

$sep1 = " "; $sep2 = "  "; $sep3 = " "

$r1c1 = Pad-Left $modelName $colW
$r1c2 = Pad-Right $userName $colW
$r1c3 = Pad-Left $ctxPctStr $colW
$r1c4 = Pad-Right $compactsStr $colW
$line1 = "$c_red$r1c1$reset$sep1$c_red$r1c2$reset$sep2$ctxColor$r1c3$reset$sep3$ctxColor$r1c4$reset"

$r2c1 = Pad-Left $sessionTimeStr $colW
$r2c2 = Pad-Right $typingTimeStr $colW
$r2c3 = Pad-Left $turnsStr $colW
$r2c4 = Pad-Right $aiCharsStr $colW
$line2 = "$c_yellow$r2c1$reset$sep1$c_yellow$r2c2$reset$sep2$c_green$r2c3$reset$sep3$c_green$r2c4$reset"

$r3c1 = Pad-Left $totalTokensStr $colW
$r3c2 = Pad-Right $promptsStr $colW
$r3c3 = Pad-Left $sessionCostStr $colW
$r3c4 = Pad-Right $totalCostStr $colW
$line3 = "$c_blue$r3c1$reset$sep1$c_blue$r3c2$reset$sep2$c_purple$r3c3$reset$sep3$c_purple$r3c4$reset"

Write-Host $line1
Write-Host $line2
Write-Host $line3
