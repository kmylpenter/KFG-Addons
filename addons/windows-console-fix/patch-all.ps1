# patch-all.ps1 - Comprehensive Windows console window fix
# Patches both TLDR daemon and Claude hooks to prevent empty console windows

$ErrorActionPreference = "Continue"
$patchCount = 0

Write-Host ""
Write-Host "  [1/2] Patching TLDR daemon (pythonw.exe fix)..." -ForegroundColor Cyan

# === PART 1: TLDR Daemon Fix ===
$startupFile = "$env:APPDATA\uv\tools\llm-tldr\Lib\site-packages\tldr\daemon\startup.py"
$pythonwPath = "$env:APPDATA\uv\tools\llm-tldr\Scripts\pythonw.exe"

# First check if pythonw.exe exists
if (-not (Test-Path $pythonwPath)) {
    Write-Host "        [WARN] pythonw.exe not found" -ForegroundColor Yellow
    Write-Host ""
    $response = Read-Host "        Czy zainstalowac llm-tldr z pythonw.exe? (t/n)"
    if ($response -eq 't' -or $response -eq 'T' -or $response -eq 'y' -or $response -eq 'Y') {
        Write-Host "        Reinstalacja llm-tldr..." -ForegroundColor Cyan
        $uvResult = uv tool install llm-tldr --force 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "        [OK] llm-tldr zainstalowany" -ForegroundColor Green
        } else {
            Write-Host "        [ERROR] Instalacja nie powiodla sie: $uvResult" -ForegroundColor Red
        }
    } else {
        Write-Host "        [SKIP] Pominieto instalacje"
    }
}

# Re-check after potential install
$pythonwPath = "$env:APPDATA\uv\tools\llm-tldr\Scripts\pythonw.exe"
if ((Test-Path $pythonwPath) -and (Test-Path $startupFile)) {
    Write-Host "        [OK] pythonw.exe found"
    $content = Get-Content $startupFile -Raw

    if ($content -match "pythonw\.exe") {
        Write-Host "        [OK] Already patched"
    } else {
        $oldPattern = '                        proc = subprocess.Popen(
                            [sys.executable, "-m", "tldr.daemon", str(project), "--foreground"],'

        $newPattern = '                        # Use pythonw.exe (GUI Python) to prevent console window
                        python_exe = sys.executable
                        if python_exe.endswith("python.exe"):
                            pythonw = python_exe.replace("python.exe", "pythonw.exe")
                            if os.path.exists(pythonw):
                                python_exe = pythonw

                        proc = subprocess.Popen(
                            [python_exe, "-m", "tldr.daemon", str(project), "--foreground"],'

        if ($content.Contains($oldPattern)) {
            $content = $content.Replace($oldPattern, $newPattern)
            Set-Content $startupFile -Value $content -NoNewline
            Write-Host "        [PATCHED] startup.py"
            $patchCount++
        } else {
            Write-Host "        [SKIP] Pattern not found (different version?)"
        }
    }
} else {
    Write-Host "        [SKIP] llm-tldr not installed"
}

# === PART 2: Claude Hooks Fix ===
Write-Host ""
Write-Host "  [2/2] Patching Claude hooks (windowsHide: true)..." -ForegroundColor Cyan

$hooksDir = "$env:USERPROFILE\.claude\hooks\src"

if (Test-Path $hooksDir) {
    # Files that need windowsHide: true added to spawnSync/spawn calls
    $filesToPatch = @(
        "daemon-client.ts",
        "skill-activation-prompt.ts",
        "memory-awareness.ts",
        "pre-tool-use-broadcast.ts",
        "handoff-index.ts",
        "session-start-tldr-cache.ts",
        "session-end-cleanup.ts"
    )

    $sharedFiles = @(
        "shared\db-utils.ts",
        "shared\db-utils-pg.ts",
        "shared\memory-client.ts",
        "shared\learning-extractor.ts"
    )

    $allFiles = $filesToPatch + $sharedFiles
    $hooksPatched = 0

    foreach ($file in $allFiles) {
        $filePath = Join-Path $hooksDir $file
        if (Test-Path $filePath) {
            $content = Get-Content $filePath -Raw

            # Check if already has windowsHide in all spawn calls
            $spawnCount = ([regex]::Matches($content, "spawnSync\(|spawn\(")).Count
            $windowsHideCount = ([regex]::Matches($content, "windowsHide:\s*true")).Count

            if ($spawnCount -gt 0 -and $windowsHideCount -lt $spawnCount) {
                # Need to add windowsHide to spawn options
                # Pattern: find spawn options objects and add windowsHide if missing

                # For spawnSync with object options
                $patterns = @(
                    # Pattern for stdio: 'ignore' without windowsHide
                    @{
                        old = "stdio: 'ignore',`n"
                        new = "stdio: 'ignore',`n            windowsHide: true,  // Prevent console window on Windows`n"
                    },
                    @{
                        old = "stdio: 'ignore'`n"
                        new = "stdio: 'ignore',`n            windowsHide: true,  // Prevent console window on Windows`n"
                    },
                    # Pattern for maxBuffer without windowsHide
                    @{
                        old = "maxBuffer: 1024 * 1024`n"
                        new = "maxBuffer: 1024 * 1024,`n        windowsHide: true,  // Prevent console window on Windows`n"
                    },
                    @{
                        old = "maxBuffer: 1024 * 1024,`n        })"
                        new = "maxBuffer: 1024 * 1024,`n        windowsHide: true,  // Prevent console window on Windows`n        })"
                    }
                )

                $modified = $false
                foreach ($p in $patterns) {
                    if ($content.Contains($p.old) -and -not $content.Contains("windowsHide")) {
                        $content = $content.Replace($p.old, $p.new)
                        $modified = $true
                    }
                }

                if ($modified) {
                    Set-Content $filePath -Value $content -NoNewline
                    Write-Host "        [PATCHED] $file"
                    $hooksPatched++
                }
            }
        }
    }

    if ($hooksPatched -gt 0) {
        $patchCount += $hooksPatched

        # Rebuild hooks
        Write-Host ""
        Write-Host "        Rebuilding hooks..." -ForegroundColor Yellow
        Push-Location "$env:USERPROFILE\.claude\hooks"
        $buildResult = npm run build 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "        [OK] Hooks rebuilt successfully"
        } else {
            Write-Host "        [WARN] Build may have issues: $buildResult" -ForegroundColor Yellow
        }
        Pop-Location
    } else {
        Write-Host "        [OK] All hooks already patched"
    }
} else {
    Write-Host "        [SKIP] Hooks directory not found"
}

# === Summary ===
Write-Host ""
if ($patchCount -gt 0) {
    Write-Host "  [DONE] Applied $patchCount patches" -ForegroundColor Green
} else {
    Write-Host "  [DONE] All files already patched" -ForegroundColor Green
}
Write-Host ""
