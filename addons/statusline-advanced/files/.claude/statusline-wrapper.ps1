# KFG Statusline Wrapper v4.0
# Linia 1: ccstatusline z dynamicznymi kolorami ctx%
# Linia 2: Cross-device Totals (compacts, typing time, AI chars, prompts, cost)

$ErrorActionPreference = 'SilentlyContinue'
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# === FUNKCJA: Parsowanie jednego .jsonl ===
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

# Kolory ANSI (6 poziomow dla context %)
$esc = [char]27
$reset = "$esc[0m"
$c_green = "$esc[38;5;46m"
$c_lime = "$esc[38;5;154m"
$c_yellow = "$esc[38;5;226m"
$c_orange = "$esc[38;5;208m"
$c_orange_red = "$esc[38;5;202m"
$c_red = "$esc[38;5;196m"
$c_blue = "$esc[38;5;39m"
$c_purple = "$esc[38;5;171m"
$c_gray = "$esc[38;5;245m"

# Czytaj JSON ze stdin
$jsonInput = [Console]::In.ReadToEnd()
$jsonInput = $jsonInput -replace '\x00', '' -replace '^\xEF\xBB\xBF', '' -replace '^\xFF\xFE', ''
if (-not $jsonInput.Trim()) { exit 0 }

$data = $jsonInput | ConvertFrom-Json
$sessionCost = 0.0
if ($data.cost -and $data.cost.total_cost_usd) { $sessionCost = [double]$data.cost.total_cost_usd }

# === BASELINES (per-file) ===
$transcriptPath = $data.transcript_path
$baselinesFile = "$env:USERPROFILE\.claude\conversation-baselines.json"

$currentMainInput = 0; $currentMainOutput = 0; $currentCost = 0.0
if ($data.context_window) {
    $cw = $data.context_window
    if ($cw.total_input_tokens) { $currentMainInput = [long]$cw.total_input_tokens }
    if ($cw.total_output_tokens) { $currentMainOutput = [long]$cw.total_output_tokens }
}
if ($data.cost -and $data.cost.total_cost_usd) { $currentCost = [double]$data.cost.total_cost_usd }

$baselines = @{}
$baselineInput = 0; $baselineOutput = 0; $baselineCost = 0.0

if (Test-Path $baselinesFile) {
    try {
        $baselinesData = Get-Content $baselinesFile -Raw | ConvertFrom-Json
        $baselinesData.PSObject.Properties | ForEach-Object { $baselines[$_.Name] = $_.Value }
    } catch {}
}

$pathKey = $transcriptPath -replace '\\', '/'
$shouldSaveBaseline = $false

if ($baselines.ContainsKey($pathKey)) {
    $bl = $baselines[$pathKey]
    $baselineInput = [long]$bl.input
    $baselineOutput = [long]$bl.output
    $baselineCost = [double]$bl.cost
} else {
    $isNewConversation = $true
    if ($transcriptPath -and (Test-Path $transcriptPath)) {
        try {
            $lineCount = (Get-Content $transcriptPath -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
            if ($lineCount -ge 20) { $isNewConversation = $false }
        } catch {}
    }
    if ($isNewConversation) {
        $baselineInput = $currentMainInput
        $baselineOutput = $currentMainOutput
        $baselineCost = $currentCost
        $shouldSaveBaseline = $true
    }
}

if ($shouldSaveBaseline) {
    $baselines[$pathKey] = @{ input = $baselineInput; output = $baselineOutput; cost = $baselineCost }
    if ($baselines.Count -gt 50) {
        $keysToRemove = $baselines.Keys | Select-Object -First ($baselines.Count - 50)
        foreach ($key in $keysToRemove) { $baselines.Remove($key) }
    }
    $baselinesJson = $baselines | ConvertTo-Json -Compress -Depth 3
    [System.IO.File]::WriteAllText($baselinesFile, $baselinesJson, [System.Text.UTF8Encoding]::new($false))
}

# === CONTEXT_LENGTH ===
$contextLength = 0
if ($data.context_length) { $contextLength = [long]$data.context_length }
elseif ($data.context_window -and $data.context_window.context_length) { $contextLength = [long]$data.context_window.context_length }
elseif ($data.context_window -and $data.context_window.current_usage) {
    $cu = $data.context_window.current_usage
    $cacheRead = if ($cu.cache_read_input_tokens) { [long]$cu.cache_read_input_tokens } else { 0 }
    $cacheCreate = if ($cu.cache_creation_input_tokens) { [long]$cu.cache_creation_input_tokens } else { 0 }
    $inputTok = if ($cu.input_tokens) { [long]$cu.input_tokens } else { 0 }
    $contextLength = $cacheRead + $cacheCreate + $inputTok
}

# === AGENT CONTRIBUTION ===
$agentContribution = Get-AgentContributionFromMain -TranscriptPath $transcriptPath
$calculatedTotal = $agentContribution

# === MAX_TOTAL TRACKING ===
$maxTotalFile = "$env:USERPROFILE\.claude\max-total-state.json"
$sessionId = $data.session_id
$transcriptSize = 0
if ($transcriptPath -and (Test-Path $transcriptPath)) { $transcriptSize = (Get-Item $transcriptPath).Length }

$maxTotal = $calculatedTotal
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
            if ($transcriptSize -lt $prevSize) { $rewindDetected = $true; $maxTotal = $calculatedTotal }
            else { $maxTotal = [Math]::Max($calculatedTotal, $savedMax) }
        }
    } catch {}
}

$allSessions[$sessionId] = @{ max_total = $maxTotal; transcript_size = $transcriptSize }
$maxState = @{ sessions = $allSessions } | ConvertTo-Json -Depth 3 -Compress
try { [System.IO.File]::WriteAllText($maxTotalFile, $maxState, [System.Text.UTF8Encoding]::new($false)) } catch {}

$totalTokens = $maxTotal
$conversationCost = $currentCost

# Formatuj total tokens
$inv = [System.Globalization.CultureInfo]::InvariantCulture
if ($totalTokens -ge 1000000) { $totalTokStr = ($totalTokens / 1000000).ToString("N1", $inv) + "M " }
elseif ($totalTokens -ge 1000) { $totalTokStr = ($totalTokens / 1000).ToString("N1", $inv) + "k " }
else { $totalTokStr = "$totalTokens " }

# === LINIA 1: ccstatusline + dynamiczne kolory ctx% ===
try {
    $tempFile = "$env:TEMP\cc-status-$PID.json"
    [System.IO.File]::WriteAllText($tempFile, $jsonInput, [System.Text.UTF8Encoding]::new($false))
    $line1 = cmd /c "type `"$tempFile`" | ccstatusline" 2>$null
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue

    if ($line1 -match '(\d+\.?\d*)%') {
        $ctxValue = [double]$Matches[1]
        $dynColor = $c_green
        if ($ctxValue -ge 85) { $dynColor = $c_red }
        elseif ($ctxValue -ge 75) { $dynColor = $c_orange_red }
        elseif ($ctxValue -ge 65) { $dynColor = $c_orange }
        elseif ($ctxValue -ge 55) { $dynColor = $c_yellow }
        elseif ($ctxValue -ge 40) { $dynColor = $c_lime }
        $line1 = $line1 -replace "$esc\[38;5;46m(\d+\.?\d*%)", "$dynColor`$1$reset"

        # Zapis ctx% dla hookow
        $ctxPctInt = [int][Math]::Round($ctxValue)
        $ctxSessionId = if ($data.session_id) { $data.session_id } else { $PID }
        $ctxCacheFile = "$env:TEMP\claude-context-pct-$ctxSessionId.txt"
        try { [System.IO.File]::WriteAllText($ctxCacheFile, "$ctxPctInt", [System.Text.UTF8Encoding]::new($false)) } catch {}
    }

    # Wstaw total tokens przed cost
    $searchStr = "$esc[38;5;171m`$"
    $insertStr = "$c_blue${totalTokStr}$reset |  $esc[38;5;171m`$"
    $line1 = $line1.Replace($searchStr, $insertStr)
} catch { $line1 = "" }

# === LINIA 2: Cross-device Totals ===
try {
    $sessionId = $data.session_id
    if (-not $sessionId) { $sessionId = "unknown" }
    $compactStateFile = "$env:USERPROFILE\.claude\compact-state.json"

    # Auto-detect stats dir
    $statsDir = $null
    $statsPaths = @("$env:USERPROFILE\.claude\stats", "D:\Projekty StriX\KFG\stats", "D:\Projekty DELL KG\KFG\stats", "C:\Projekty\KFG\stats")
    foreach ($p in $statsPaths) { if (Test-Path $p) { $statsDir = $p; break } }

    # Compact counter
    $compactsCount = 0
    $currentCtxLength = $contextLength
    if (Test-Path $compactStateFile) {
        try {
            $compactState = Get-Content $compactStateFile -Raw | ConvertFrom-Json
            if ($compactState.session_id -eq $sessionId) {
                $compactsCount = [int]$compactState.count
                $prevCtxLength = [long]$compactState.last_context_length
                if ($currentCtxLength -gt 0 -and $prevCtxLength -gt 0 -and -not $rewindDetected) {
                    if ($currentCtxLength -lt ($prevCtxLength * 0.9)) { $compactsCount++ }
                }
            }
        } catch {}
    }
    $newState = @{ session_id = $sessionId; count = $compactsCount; last_context_length = $currentCtxLength } | ConvertTo-Json -Compress
    try { [System.IO.File]::WriteAllText($compactStateFile, $newState, [System.Text.UTF8Encoding]::new($false)) } catch {}

    # Agreguj dane z device-*.json
    $totalCharsUser = 0; $totalCharsAi = 0; $totalUserPrompts = 0; $totalCost = 0.0
    if (Test-Path $statsDir) {
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

    # Formatowanie czasu pisania (chars_user / 285 char/min)
    $typingMinutes = if ($totalCharsUser -gt 0) { $totalCharsUser / 285 } else { 0 }
    $typingHours = [math]::Floor($typingMinutes / 60)
    $typingMins = [math]::Floor($typingMinutes % 60)
    $timeStr = if ($typingHours -gt 0) { "${typingHours}h ${typingMins}m" } else { "${typingMins}m" }

    # Formatowanie znakow AI
    if ($totalCharsAi -ge 1000000) { $charsAiStr = ($totalCharsAi / 1000000).ToString("N2", $inv) + "M" }
    elseif ($totalCharsAi -ge 1000) { $charsAiStr = ($totalCharsAi / 1000).ToString("N1", $inv) + "k" }
    else { $charsAiStr = "$totalCharsAi" }

    # User Prompts
    if ($totalUserPrompts -ge 1000) { $userPromptsStr = ($totalUserPrompts / 1000).ToString("N1", $inv) + "k" }
    else { $userPromptsStr = "$totalUserPrompts" }

    # Koszt
    if ($totalCost -ge 1000) { $costStr = "`$" + ($totalCost / 1000).ToString("N1", $inv) + "k" }
    else { $costStr = "`$" + $totalCost.ToString("N2", $inv) }

    # Dynamiczne szerokosci kolumn z linii 1
    $line1Visible = $line1 -replace '\x1b\[[0-9;]*m', ''
    $pipePos = @()
    for ($i = 0; $i -lt $line1Visible.Length; $i++) { if ($line1Visible[$i] -eq '|') { $pipePos += $i } }

    $w = @()
    if ($pipePos.Count -ge 5) {
        $w += $pipePos[0]
        $w += $pipePos[1] - $pipePos[0] - 1
        $w += $pipePos[2] - $pipePos[1] - 1
        $w += $pipePos[3] - $pipePos[2] - 1
        $w += $pipePos[4] - $pipePos[3] - 1
    } else { $w = @(11, 9, 10, 9, 6) }

    function Center-Col([string]$text, [int]$width) {
        $pad = $width - $text.Length
        if ($pad -lt 0) { return $text.Substring(0, $width) }
        $padL = [int][Math]::Floor($pad / 2)
        $padR = $pad - $padL
        return (" " * $padL) + $text + (" " * $padR)
    }

    $c1 = Center-Col "Totals:" $w[0]
    $c2 = Center-Col "$compactsCount" $w[1]
    $c3 = Center-Col "$timeStr" $w[2]
    $c4 = Center-Col "$charsAiStr" $w[3]
    $c5 = Center-Col "$userPromptsStr" $w[4]

    $line2 = "$c_gray$c1$reset|$c_gray$c2$reset|$c_yellow$c3$reset|$c_green$c4$reset|$c_blue$c5$reset|  $c_purple$costStr$reset"
} catch { $line2 = "" }

# === OUTPUT ===
if ($line1) { Write-Host $line1 }
if ($line2) { Write-Host $line2 }
