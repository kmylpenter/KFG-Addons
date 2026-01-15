# Analiza historycznych sesji Claude Code
# Przechodzi przez wszystkie .jsonl i sumuje tokeny z kazdej wiadomosci
# v3.0: Filtrowanie po cwd WEWNATRZ plikow (Dell vs DELL w tym samym folderze)

param(
    [switch]$Verbose,
    [string]$DeviceFilter = "",  # Pusty = wszystkie, "STRIX", "DELL", "Dell", "ANDROID"
    [string]$OutputFile = ""     # Pusty = domyslny totals-history.json
)

$projectsDir = "$env:USERPROFILE\.claude\projects"
$historyFile = if ($OutputFile) { $OutputFile } else { "$env:USERPROFILE\.claude\totals-history.json" }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "        ANALIZA HISTORYCZNYCH SESJI CLAUDE CODE             " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
if ($DeviceFilter) {
    Write-Host "        Filtr urzadzenia: $DeviceFilter (po cwd w sesji)" -ForegroundColor Yellow
}
Write-Host ""

# Funkcja: wyodrebnij device z cwd
function Get-DeviceFromCwd {
    param([string]$Cwd)
    if (-not $Cwd) { return $null }

    # Windows: C:\Users\USERNAME\...
    if ($Cwd -cmatch "^C:\\Users\\([^\\]+)\\") {
        return $Matches[1]
    }
    # Windows: D:\Projekty DELL KG\... lub D:\Projekty StriX\...
    if ($Cwd -cmatch "^[A-Z]:\\Projekty ([^\\]+)\\") {
        $deviceName = $Matches[1]
        if ($deviceName -eq "DELL KG") { return "DELL" }
        if ($deviceName -eq "StriX") { return "kamil" }
        return $deviceName
    }
    # Android: /data/data/com.termux/...
    if ($Cwd -like "/data/data/com.termux/*") {
        return "ANDROID"
    }
    return $null
}

# Funkcja: wyodrebnij device z nazwy folderu (fallback dla starszych sesji)
function Get-DeviceFromFolderName {
    param([string]$FolderName)
    if (-not $FolderName) { return $null }

    # C--Users-USERNAME-... (case-sensitive!)
    if ($FolderName -cmatch "^C--Users-([^-]+)-") {
        return $Matches[1]
    }
    # D--Projekty-DELL-KG-... lub D--Projekty-StriX-...
    if ($FolderName -cmatch "^[A-Z]--Projekty-DELL-KG-") {
        return "DELL"
    }
    if ($FolderName -cmatch "^[A-Z]--Projekty-StriX-") {
        return "kamil"
    }
    # android--...
    if ($FolderName -like "android--*") {
        return "ANDROID"
    }
    return $null
}

# Funkcja: sprawdz czy sesja pasuje do filtra
function Test-DeviceMatch {
    param([string]$Device, [string]$Filter)
    if (-not $Filter) { return $true }  # brak filtra = wszystkie

    switch ($Filter) {
        "STRIX"   { return $Device -ceq "kamil" }
        "DELL"    { return $Device -ceq "DELL" }
        "DESKTOP-94BP3P3" { return $Device -ceq "DELL" }  # Laptop DELL (COMPUTERNAME)
        "Dell"    { return $Device -ceq "Dell" }
        "ANDROID" { return $Device -ceq "ANDROID" }
        default   { return $Device -ceq $Filter }
    }
}

# Znajdz wszystkie foldery projektow (skanuj wszystkie, filtruj pozniej)
$allFolders = Get-ChildItem -Path $projectsDir -Directory -ErrorAction SilentlyContinue

if (-not $allFolders) {
    Write-Host "Brak folderow projektow w: $projectsDir" -ForegroundColor Red
    exit 1
}

Write-Host "Skanowanie $($allFolders.Count) folderow projektow..." -ForegroundColor Yellow
Write-Host ""

$globalStats = @{
    total_input_tokens = 0
    total_output_tokens = 0
    total_cache_read = 0
    total_cache_write = 0
    total_agent_savings = 0
    sessions_count = 0
    messages_count = 0
    user_prompts_count = 0
    chars_user_total = 0    # v4.0
    chars_ai_total = 0      # v4.0
    files_processed = 0
    files_skipped = 0
}

$sessionsData = @{}

foreach ($project in $allFolders) {
    # Znajdz pliki sesji (UUID.jsonl, nie agent-*)
    $sessionFiles = Get-ChildItem -Path $project.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.jsonl$" }

    if ($Verbose) {
        Write-Host "  $($project.Name): $($sessionFiles.Count) sesji" -ForegroundColor Gray
    }

    foreach ($file in $sessionFiles) {
        $sessionId = $file.BaseName

        # Pomin duplikaty (ten sam session moze byc w wielu folderach)
        if ($sessionsData.ContainsKey($sessionId)) { continue }

        $sessionCwd = $null
        $sessionDevice = $null
        $sessionTokensIn = 0
        $sessionTokensOut = 0
        $sessionCacheRead = 0
        $sessionCacheWrite = 0
        $sessionAgentSavings = 0
        $sessionMessages = 0
        $sessionUserPrompts = 0
        $sessionCharsUser = 0    # v4.0: znaki promptów usera
        $sessionCharsAi = 0      # v4.0: znaki odpowiedzi AI
        $sessionStart = $null
        $sessionEnd = $null

        try {
            # Czytaj plik linia po linii
            $lines = Get-Content $file.FullName -ErrorAction SilentlyContinue

            foreach ($line in $lines) {
                if (-not $line.Trim()) { continue }

                try {
                    $msg = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if (-not $msg) { continue }

                    # Wyodrebnij cwd z pierwszej wiadomosci user (case-sensitive!)
                    if (-not $sessionCwd -and $msg.cwd) {
                        $sessionCwd = $msg.cwd
                        $sessionDevice = Get-DeviceFromCwd $sessionCwd
                    }

                    # Timestamp
                    if ($msg.timestamp) {
                        if (-not $sessionStart) { $sessionStart = $msg.timestamp }
                        $sessionEnd = $msg.timestamp
                    }

                    # User prompts (type=user, bez meta/systemowych, bez agentów)
                    # v4.0: + filtr Warmup + liczenie znaków
                    if ($msg.type -eq "user" -and -not $msg.isMeta -and -not $msg.isSidechain) {
                        $content = if ($msg.message -and $msg.message.content) { $msg.message.content } else { "" }
                        # Wyciągnij tekst jeśli content to array
                        if ($content -is [array]) {
                            $textParts = @()
                            foreach ($c in $content) {
                                if ($c.type -eq "text" -and $c.text) { $textParts += $c.text }
                            }
                            $content = $textParts -join ""
                        }
                        # Filtruj: command-name, local-command, Warmup
                        $isCommand = $content -match "^<command-name>" -or $content -match "^<local-command"
                        $isWarmup = $content.Trim() -eq "Warmup"
                        if ($content -and -not $isCommand -and -not $isWarmup) {
                            $sessionUserPrompts++
                            $sessionCharsUser += $content.Length
                        }
                    }

                    # v4.1: Znaki AI z odpowiedzi assistant (text + tool_use content)
                    if ($msg.type -eq "assistant" -and $msg.message -and $msg.message.content) {
                        $aiContent = $msg.message.content
                        if ($aiContent -is [string]) {
                            $sessionCharsAi += $aiContent.Length
                        } elseif ($aiContent -is [array]) {
                            foreach ($c in $aiContent) {
                                # Tekst odpowiedzi
                                if ($c.type -eq "text" -and $c.text) {
                                    $sessionCharsAi += $c.text.Length
                                }
                                # Kod z Write/Edit (tool_use)
                                if ($c.type -eq "tool_use" -and $c.input) {
                                    # Write: input.content
                                    if ($c.input.content) {
                                        $sessionCharsAi += $c.input.content.Length
                                    }
                                    # Edit: input.new_string
                                    if ($c.input.new_string) {
                                        $sessionCharsAi += $c.input.new_string.Length
                                    }
                                }
                            }
                        }
                    }

                    # Usage z message
                    if ($msg.message -and $msg.message.usage) {
                        $usage = $msg.message.usage
                        $sessionTokensIn += if ($usage.input_tokens) { $usage.input_tokens } else { 0 }
                        $sessionTokensOut += if ($usage.output_tokens) { $usage.output_tokens } else { 0 }
                        $sessionCacheRead += if ($usage.cache_read_input_tokens) { $usage.cache_read_input_tokens } else { 0 }
                        $sessionCacheWrite += if ($usage.cache_creation_input_tokens) { $usage.cache_creation_input_tokens } else { 0 }
                        $sessionMessages++
                    }

                    # Agent savings z toolUseResult (Task tool)
                    if ($msg.toolUseResult -and $msg.toolUseResult.totalTokens) {
                        $tur = $msg.toolUseResult
                        $agentTotalTokens = [long]$tur.totalTokens

                        # Estymuj summary tokens (4 chars ~ 1 token)
                        $summaryTokens = 0
                        if ($tur.content -and $tur.content.Count -gt 0) {
                            foreach ($c in $tur.content) {
                                if ($c.text) {
                                    $summaryTokens += [math]::Ceiling($c.text.Length / 4)
                                }
                            }
                        }

                        $contribution = $agentTotalTokens - $summaryTokens
                        if ($contribution -gt 0) {
                            $sessionAgentSavings += $contribution
                        }
                    }

                } catch { }
            }

            # Fallback: jesli brak cwd, uzyj nazwy folderu (starsze sesje)
            if (-not $sessionDevice) {
                $sessionDevice = Get-DeviceFromFolderName $project.Name
            }

            # Sprawdz czy sesja pasuje do filtra (case-sensitive!)
            if ($DeviceFilter -and -not (Test-DeviceMatch $sessionDevice $DeviceFilter)) {
                $globalStats.files_skipped++
                $globalStats.files_processed++
                continue
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
                    chars_user = $sessionCharsUser      # v4.0
                    chars_ai = $sessionCharsAi          # v4.0
                    device = $sessionDevice
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
                $globalStats.chars_user_total += $sessionCharsUser    # v4.0
                $globalStats.chars_ai_total += $sessionCharsAi        # v4.0
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
        chars_user_total = $globalStats.chars_user_total    # v4.0
        chars_ai_total = $globalStats.chars_ai_total        # v4.0
    }
    total_cost = [math]::Round($totalCost, 2)
    total_duration_ms = $totalDurMs
    total_tokens_main = $totalTokMain
    total_tokens_total = $totalTokTotal
    total_agent_savings = $totalAgentSavings
    total_user_prompts = $globalStats.user_prompts_count
    total_chars_user = $globalStats.chars_user_total        # v4.0
    total_chars_ai = $globalStats.chars_ai_total            # v4.0
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
if ($DeviceFilter) {
    Write-Host "  Plikow pominietych:     $($globalStats.files_skipped) (inny device)" -ForegroundColor DarkGray
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
