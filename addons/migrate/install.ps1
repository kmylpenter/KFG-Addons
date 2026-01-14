# ============================================================
# Migrate Addon Installer
# ============================================================

param(
    [string]$TargetBase = $env:USERPROFILE
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Installing: Migrate Claude History" -ForegroundColor Cyan

# Targets
$targets = @{
    "files\skills\migrate\" = ".claude\skills\migrate\"
    "files\templates\scripts\" = ".templates\scripts\"
}

foreach ($source in $targets.Keys) {
    $sourcePath = Join-Path $scriptDir $source
    $targetPath = Join-Path $TargetBase $targets[$source]

    if (Test-Path $sourcePath) {
        # Create target directory if not exists
        $targetDir = Split-Path -Parent $targetPath
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        # Copy files
        Copy-Item -Path "$sourcePath*" -Destination $targetPath -Recurse -Force
        Write-Host "  Copied: $source -> $targetPath" -ForegroundColor Green
    }
}

Write-Host "Migrate addon installed!" -ForegroundColor Green
