# KMYLPENTER Windows 11 Accent Color
# Osobny skrypt - modyfikuje rejestr Windows (moze triggerowac AV)
# Uruchom recznie: powershell -ExecutionPolicy Bypass -File set-windows-accent.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  === KMYLPENTER Windows 11 Accent Color ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Ten skrypt ustawi kolor akcentu Windows 11 na KMYLPENTER Blue (#3A90C8)" -ForegroundColor White
Write-Host "  Dotyczy: pasek zadan, ramki okien, przyciski, Start menu" -ForegroundColor Gray
Write-Host ""
Write-Host "  UWAGA: Modyfikuje rejestr Windows - moze wywolac alert antywirusowy" -ForegroundColor Yellow
Write-Host ""

$choice = Read-Host "  Kontynuowac? [t/N]"

if ($choice -notmatch "^[TtYy]") {
    Write-Host "  Anulowano." -ForegroundColor Gray
    exit 0
}

try {
    # Convert hex to BGR (Windows uses BGR format)
    # #3A90C8 -> RGB(58, 144, 200) -> BGR: 0x00C8903A
    $blueLight = 0x00C8903A
    # M_INFERRED: ColorizationColor/Afterglow to ARGB - DWM oczekuje pelnej alpha (0xFF),
    # alpha 0x00 daje "przezroczysty" kolor. AccentColor (ABGR) zostawiamy bez zmian.
    $blueLightArgb = 0xFFC8903A

    # Set accent color in registry
    $dwmPath = "HKCU:\SOFTWARE\Microsoft\Windows\DWM"
    $themePath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize"

    # M_INFERRED: backup starych wartosci rejestru przed nadpisaniem (jak cofnac - ponizej)
    $dwmBackupNames = @("AccentColor", "ColorizationColor", "ColorizationAfterglow", "ColorPrevalence")
    $dwmBackup = @{}
    foreach ($name in $dwmBackupNames) {
        $old = (Get-ItemProperty -Path $dwmPath -Name $name -ErrorAction SilentlyContinue).$name
        if ($null -ne $old) { $dwmBackup[$name] = $old }
    }
    if ($dwmBackup.Count -gt 0) {
        Write-Host "  --> Backup starych wartosci DWM (aby cofnac, ustaw je z powrotem):" -ForegroundColor Cyan
        foreach ($name in $dwmBackup.Keys) {
            Write-Host ("      {0} = 0x{1:X8}" -f $name, $dwmBackup[$name]) -ForegroundColor Gray
        }
    } else {
        Write-Host "  --> Brak poprzednich wartosci DWM (aby cofnac: usun dodane klucze z $dwmPath)" -ForegroundColor Cyan
    }

    # Enable custom accent color
    Set-ItemProperty -Path $dwmPath -Name "AccentColor" -Value $blueLight -Type DWord -Force
    Set-ItemProperty -Path $dwmPath -Name "ColorizationColor" -Value $blueLightArgb -Type DWord -Force
    Set-ItemProperty -Path $dwmPath -Name "ColorizationAfterglow" -Value $blueLightArgb -Type DWord -Force

    # Set color prevalence (show accent color on title bars and window borders)
    Set-ItemProperty -Path $dwmPath -Name "ColorPrevalence" -Value 1 -Type DWord -Force

    # Enable accent color on Start and taskbar
    if (Test-Path $themePath) {
        Set-ItemProperty -Path $themePath -Name "ColorPrevalence" -Value 1 -Type DWord -Force
    }

    Write-Host ""
    Write-Host "  [OK] Ustawiono kolor akcentu Windows 11" -ForegroundColor Green
    Write-Host "  --> Moze wymagac wylogowania/ponownego uruchomienia" -ForegroundColor Cyan
    Write-Host ""

} catch {
    Write-Host ""
    Write-Host "  [!] Blad: $_" -ForegroundColor Red
    Write-Host "  --> Ustaw recznie: Ustawienia > Personalizacja > Kolory > Kolor akcentu" -ForegroundColor Cyan
    Write-Host ""
}
