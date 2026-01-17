# CCv3 Structure Check - Postinstall Script
$ErrorActionPreference = "Stop"

$hooksDir = Join-Path $env:ADDON_DIR "hooks"

Write-Host "Installing dependencies..."
Push-Location $hooksDir
try {
    npm install --silent 2>$null
    if ($LASTEXITCODE -ne 0) { throw "npm install failed" }

    Write-Host "Building hooks..."
    npm run build --silent 2>$null
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }

    Write-Host "[OK] CCv3 Structure Check hooks compiled"
} finally {
    Pop-Location
}
