# Patch settings.json: statusline PS1 -> Node.js
# Wywoływany jako postinstall przez install-addons.ps1

$settingsPath = "$env:USERPROFILE\.claude\settings.json"
if (-not (Test-Path $settingsPath)) {
    Write-Host "    [!] settings.json nie znaleziony" -ForegroundColor Yellow
    return
}

$content = Get-Content $settingsPath -Raw
$userHome = $env:USERPROFILE -replace '\\', '/'
$newCmd = "node $userHome/.claude/statusline-wrapper.mjs"

# Zamien dowolna komende statusline PS1 na Node.js
if ($content -match '"command"\s*:\s*"[^"]*statusline-wrapper\.ps1"') {
    $content = $content -replace '"command"\s*:\s*"[^"]*statusline-wrapper\.ps1"', "`"command`":  `"$newCmd`""
    $content | Set-Content $settingsPath -Encoding UTF8 -NoNewline
    Write-Host "    [OK] settings.json: statusline -> Node.js ($newCmd)" -ForegroundColor Green
}
# Jesli juz jest Node.js - skip
elseif ($content -match 'statusline-wrapper\.mjs') {
    Write-Host "    [~] settings.json: juz ustawiony na Node.js" -ForegroundColor DarkGray
}
# Jesli ustawiony na capture wrapper - zamien tez
elseif ($content -match '"command"\s*:\s*"[^"]*statusline-capture\.mjs"') {
    $content = $content -replace '"command"\s*:\s*"[^"]*statusline-capture\.mjs"', "`"command`":  `"$newCmd`""
    $content | Set-Content $settingsPath -Encoding UTF8 -NoNewline
    Write-Host "    [OK] settings.json: statusline capture -> Node.js" -ForegroundColor Green
}
else {
    Write-Host "    [!] settings.json: nie znaleziono komendy statusline do zamiany" -ForegroundColor Yellow
    Write-Host "    Dodaj recznie: `"command`": `"$newCmd`"" -ForegroundColor Gray
}
