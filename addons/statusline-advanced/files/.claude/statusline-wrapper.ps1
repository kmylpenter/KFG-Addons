# KFG Statusline Wrapper v5.1
# Format 4x3 z poziomym parowaniem SESJA/TOTAL
#
# Rzad 1: Model/Device | ctx%/compacts
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

# === FUNKCJA: Parsowanie tokenow z .jsonl ===
function Get-TokensFromSingleJsonl {
    param([string]$Path, [switch]$OutputOnly)
    $tokens = 0
    if (-not $Path -or -not (Test-Path $Path)) { return 0 }
    try {
        $fileStream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8)
        while ($null -ne ($line = $reader.ReadLine())) {
            if (-not $line.Trim()) { continue }
            try {
                $entry = $line | ConvertFrom-Json
                $usage = $entry.message.usage
                if ($usage) {
                    $outp = if ($usage.output_tokens) { [long]$usage.output_tokens } else { 0 }
                    if ($OutputOnly) { $tokens += $outp }
                    else {
                        $inp = if ($usage.input_tokens) { [long]$usage.input_tokens } else { 0 }
                        $tokens += $inp + $outp
                    }
                }
            } catch {}
        }
        $reader.Close(); $reader.Dispose(); $fileStream.Dispose()
    } catch {}
    return $tokens
}

# === FUNKCJA: Agent contribution z toolUseResult ===
function Get-AgentContributionFromMain {
    param([string]$TranscriptPath)
    $totalContribution = 0
    if (-not $TranscriptPath -or -not (Test-Path $TranscriptPath)) { return 0 }
    try {
        $fileStream = [System.IO.FileStream]::new($TranscriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8)
        while ($null -ne ($line = $reader.ReadLine())) {
            if (-not $line.Trim()) { continue }
            if ($line -notmatch 'toolUseResult') { continue }
            try {
                $entry = $line | ConvertFrom-Json
                $tur = $entry.toolUseResult
                if ($tur -and $tur.usage) {
                    $agentInput = if ($tur.usage.input_tokens) { [long]$tur.usage.input_tokens } else { 0 }
                    $agentCacheCreate = if ($tur.usage.cache_creation_input_tokens) { [long]$tur.usage.cache_creation_input_tokens } else { 0 }
                    $agentOutput = if ($tur.usage.output_tokens) { [long]$tur.usage.output_tokens } else { 0 }
                    $agentNewWork = $agentInput + $agentCacheCreate + $agentOutput
                    $summaryTokens = 0
                    if ($tur.content -and $tur.content.Count -gt 0) {
                        foreach ($c in $tur.content) {
                            if ($c.text) { $summaryTokens += [math]::Ceiling($c.text.Length / 4) }
                        }
                    }
                    $contribution = $agentNewWork - $summaryTokens
                    if ($contribution -gt 0) { $totalContribution += $contribution }
                }
            } catch {}
        }
        $reader.Close(); $reader.Dispose(); $fileStream.Dispose()
    } catch {}
    return $totalContribution
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

# === FUNKCJA: Context length z transcript (jak ccstatusline) ===
function Get-ContextFromTranscript {
    param([string]$TranscriptPath)

    $result = @{ contextLength = 0; turns = 0; firstTimestamp = $null; lastTimestamp = $null }
    if (-not $TranscriptPath -or -not (Test-Path $TranscriptPath)) { return $result }

    $mostRecentTimestamp = $null
    $mostRecentUsage = $null

    try {
        $fileStream = [System.IO.FileStream]::new($TranscriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($fileStream, [System.Text.Encoding]::UTF8)

        while ($null -ne ($line = $reader.ReadLine())) {
            if (-not $line.Trim()) { continue }
            try {
                $entry = $line | ConvertFrom-Json

                # Zliczaj turns (user messages)
                if ($entry.type -eq 'user') { $result.turns++ }

                # Track timestamps for session duration
                if ($entry.timestamp) {
                    $ts = [DateTime]::Parse($entry.timestamp)
                    if (-not $result.firstTimestamp -or $ts -lt $result.firstTimestamp) {
                        $result.firstTimestamp = $ts
                    }
                    if (-not $result.lastTimestamp -or $ts -gt $result.lastTimestamp) {
                        $result.lastTimestamp = $ts
                    }
                }

                # Context length: najnowszy main chain entry z usage (nie sidechain, nie error)
                if ($entry.message -and $entry.message.usage) {
                    $isSidechain = $entry.isSidechain -eq $true
                    $isError = $entry.isApiErrorMessage -eq $true

                    if (-not $isSidechain -and -not $isError -and $entry.timestamp) {
                        $entryTime = [DateTime]::Parse($entry.timestamp)
                        if (-not $mostRecentTimestamp -or $entryTime -gt $mostRecentTimestamp) {
                            $mostRecentTimestamp = $entryTime
                            $mostRecentUsage = $entry.message.usage
                        }
                    }
                }
            } catch {}
        }
        $reader.Close(); $reader.Dispose(); $fileStream.Dispose()
    } catch {}

    # Oblicz contextLength z najnowszego usage
    if ($mostRecentUsage) {
        $inputTok = if ($mostRecentUsage.input_tokens) { [long]$mostRecentUsage.input_tokens } else { 0 }
        $cacheRead = if ($mostRecentUsage.cache_read_input_tokens) { [long]$mostRecentUsage.cache_read_input_tokens } else { 0 }
        $cacheCreate = if ($mostRecentUsage.cache_creation_input_tokens) { [long]$mostRecentUsage.cache_creation_input_tokens } else { 0 }
        $result.contextLength = $inputTok + $cacheRead + $cacheCreate
    }

    return $result
}


# === FUNKCJA: Formatowanie liczb ===
function Format-Number {
    param([long]$Num, [string]$Suffix = "")
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Num -ge 1000000) { return ($Num / 1000000).ToString("N1", $inv) + "M$Suffix" }
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
$jsonInput = $jsonInput -replace '\x00', '' -replace '^\xEF\xBB\xBF', '' -replace '^\xFF\xFE', ''
if (-not $jsonInput.Trim()) { exit 0 }

$data = $jsonInput | ConvertFrom-Json

# === PARSOWANIE DANYCH SESJI ===
$sessionCost = 0.0
if ($data.cost -and $data.cost.total_cost_usd) { $sessionCost = [double]$data.cost.total_cost_usd }

# Model name (skrocona wersja np. O4.5, S3.5, H3)
$modelName = "?"
$rawModel = $null

# ccstatusline uzywa model.id i model.display_name
if ($data.model) {
    if ($data.model.id) {
        $rawModel = $data.model.id
    } elseif ($data.model.display_name) {
        $rawModel = $data.model.display_name
    }
}

if ($rawModel) {
    # Wyciagnij wersje z nazwy modelu (np. claude-opus-4-5-20251101 -> 4.5)
    $version = ""
    if ($rawModel -match '(\d+)-(\d+)-\d{8}') {
        $version = "$($Matches[1]).$($Matches[2])"
    } elseif ($rawModel -match '(\d+)-\d{8}') {
        $version = $Matches[1]
    } elseif ($rawModel -match '(\d+\.\d+)') {
        $version = $Matches[1]
    }

    # Skroc nazwe modelu do O/S/H + wersja
    if ($rawModel -match 'opus') { $modelName = "O$version" }
    elseif ($rawModel -match 'sonnet') { $modelName = "S$version" }
    elseif ($rawModel -match 'haiku') { $modelName = "H$version" }
    else { $modelName = "C$version" }
}

# Device name
$deviceName = $env:COMPUTERNAME
if (-not $deviceName) { $deviceName = "LOCAL" }

# === CONTEXT, TURNS, SESSION DURATION z transcript ===
$transcriptPath = $data.transcript_path
$transcriptData = Get-ContextFromTranscript -TranscriptPath $transcriptPath

$contextLength = $transcriptData.contextLength
$contextLimit = 200000  # Default limit dla Opus/Sonnet
$contextPct = 0.0

if ($contextLimit -gt 0 -and $contextLength -gt 0) {
    $contextPct = [math]::Round(($contextLength / $contextLimit) * 100, 1)
}

# Turns z transcript
$turns = $transcriptData.turns

# Session duration z timestamps
$sessionDuration = 0
if ($transcriptData.firstTimestamp -and $transcriptData.lastTimestamp) {
    $sessionDuration = [int]($transcriptData.lastTimestamp - $transcriptData.firstTimestamp).TotalSeconds
}

# Zapis ctx% dla hookow
$ctxPctInt = [int][Math]::Round($contextPct)
$ctxSessionId = if ($data.session_id) { $data.session_id } else { $PID }
$ctxCacheFile = "$env:TEMP\claude-context-pct-$ctxSessionId.txt"
try { [System.IO.File]::WriteAllText($ctxCacheFile, "$ctxPctInt", [System.Text.UTF8Encoding]::new($false)) } catch {}

# === AGENT CONTRIBUTION / TOTAL TOKENS ===
$transcriptPath = $data.transcript_path
$agentContribution = Get-AgentContributionFromMain -TranscriptPath $transcriptPath
$totalTokens = $agentContribution

# === MAX_TOTAL TRACKING ===
$maxTotalFile = "$env:USERPROFILE\.claude\max-total-state.json"
$sessionId = $data.session_id
$transcriptSize = 0
if ($transcriptPath -and (Test-Path $transcriptPath)) { $transcriptSize = (Get-Item $transcriptPath).Length }

$maxTotal = $totalTokens
$rewindDetected = $false
$allSessions = @{}

if (Test-Path $maxTotalFile) {
    try {
        $maxState = Get-Content $maxTotalFile -Raw | ConvertFrom-Json
        if ($maxState.sessions) {
            $maxState.sessions.PSObject.Properties | ForEach-Object {
                $allSessions[$_.Name] = @{ max_total = [long]$_.Value.max_total; transcript_size = [long]$_.Value.transcript_size }
            }
        }
        if ($allSessions.ContainsKey($sessionId)) {
            $prevSize = $allSessions[$sessionId].transcript_size
            $savedMax = $allSessions[$sessionId].max_total
            if ($transcriptSize -lt $prevSize) { $rewindDetected = $true; $maxTotal = $totalTokens }
            else { $maxTotal = [Math]::Max($totalTokens, $savedMax) }
        }
    } catch {}
}

$allSessions[$sessionId] = @{ max_total = $maxTotal; transcript_size = $transcriptSize }
$maxState = @{ sessions = $allSessions } | ConvertTo-Json -Depth 3 -Compress
try { [System.IO.File]::WriteAllText($maxTotalFile, $maxState, [System.Text.UTF8Encoding]::new($false)) } catch {}

$totalTokens = $maxTotal

# === COMPACT COUNTER ===
$compactStateFile = "$env:USERPROFILE\.claude\compact-state.json"
$compactsCount = 0

if (Test-Path $compactStateFile) {
    try {
        $compactState = Get-Content $compactStateFile -Raw | ConvertFrom-Json
        if ($compactState.session_id -eq $sessionId) {
            $compactsCount = [int]$compactState.count
            $prevCtxLength = [long]$compactState.last_context_length
            if ($contextLength -gt 0 -and $prevCtxLength -gt 0 -and -not $rewindDetected) {
                if ($contextLength -lt ($prevCtxLength * 0.9)) { $compactsCount++ }
            }
        }
    } catch {}
}
$newState = @{ session_id = $sessionId; count = $compactsCount; last_context_length = $contextLength } | ConvertTo-Json -Compress
try { [System.IO.File]::WriteAllText($compactStateFile, $newState, [System.Text.UTF8Encoding]::new($false)) } catch {}

# === CROSS-DEVICE TOTALS ===
$statsDir = $null
$statsPaths = @("$env:USERPROFILE\.claude\stats", "D:\Projekty StriX\KFG\stats", "D:\Projekty DELL KG\KFG\stats", "C:\Projekty\KFG\stats")
foreach ($p in $statsPaths) { if (Test-Path $p) { $statsDir = $p; break } }

$totalCharsUser = 0; $totalCharsAi = 0; $totalUserPrompts = 0; $totalCost = 0.0
if ($statsDir -and (Test-Path $statsDir)) {
    Get-ChildItem "$statsDir\device-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $dev = Get-Content $_.FullName -Raw | ConvertFrom-Json
            $totalCharsUser += if ($dev.chars_user) { [long]$dev.chars_user } else { 0 }
            $totalCharsAi += if ($dev.chars_ai) { [long]$dev.chars_ai } else { 0 }
            $totalUserPrompts += if ($dev.user_prompts) { [int]$dev.user_prompts } else { 0 }
            $totalCost += [double]$dev.cost
        } catch {}
    }
}

# Typing time (total) - chars_user / 285 char/min
$typingMinutes = if ($totalCharsUser -gt 0) { $totalCharsUser / 285 } else { 0 }
$typingHours = [math]::Floor($typingMinutes / 60)
$typingMins = [math]::Floor($typingMinutes % 60)
$typingTimeStr = if ($typingHours -gt 0) { "${typingHours}h${typingMins}m" } else { "${typingMins}m" }

# === FORMATOWANIE WARTOSCI ===
$inv = [System.Globalization.CultureInfo]::InvariantCulture

$ctxPctStr = "$contextPct%"
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
# Szerokosci kolumn
$colW = 8

# Wyrownanie: kolumna 1,3 do prawej, kolumna 2,4 do lewej
function Pad-Right([string]$text, [int]$width) {
    if ($text.Length -ge $width) { return $text.Substring(0, $width) }
    return (" " * ($width - $text.Length)) + $text
}

function Pad-Left([string]$text, [int]$width) {
    if ($text.Length -ge $width) { return $text.Substring(0, $width) }
    return $text + (" " * ($width - $text.Length))
}

# Separatory (stale dla wszystkich linii)
$sep1 = " "   # miedzy col1 i col2
$sep2 = "  "  # miedzy para 1 i para 2
$sep3 = " "   # miedzy col3 i col4

# Rzad 1: Model/Device | ctx%/compacts (czerwony | dynamiczny)
# Kolumny 1,3 do lewej - kolumny 2,4 do prawej
$r1c1 = Pad-Left $modelName $colW
$r1c2 = Pad-Right $deviceName $colW
$r1c3 = Pad-Left $ctxPctStr $colW
$r1c4 = Pad-Right $compactsStr $colW

$line1 = "$c_red$r1c1$reset$sep1$c_red$r1c2$reset$sep2$ctxColor$r1c3$reset$sep3$ctxColor$r1c4$reset"

# Rzad 2: czas/typing | turns/AI_chars (zolty | zielony)
$r2c1 = Pad-Left $sessionTimeStr $colW
$r2c2 = Pad-Right $typingTimeStr $colW
$r2c3 = Pad-Left $turnsStr $colW
$r2c4 = Pad-Right $aiCharsStr $colW

$line2 = "$c_yellow$r2c1$reset$sep1$c_yellow$r2c2$reset$sep2$c_green$r2c3$reset$sep3$c_green$r2c4$reset"

# Rzad 3: tokens/prompts | cost/cost_t (niebieski | fioletowy)
$r3c1 = Pad-Left $totalTokensStr $colW
$r3c2 = Pad-Right $promptsStr $colW
$r3c3 = Pad-Left $sessionCostStr $colW
$r3c4 = Pad-Right $totalCostStr $colW

$line3 = "$c_blue$r3c1$reset$sep1$c_blue$r3c2$reset$sep2$c_purple$r3c3$reset$sep3$c_purple$r3c4$reset"

# === OUTPUT ===
Write-Host $line1
Write-Host $line2
Write-Host $line3
