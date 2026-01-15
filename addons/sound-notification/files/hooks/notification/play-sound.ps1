# Sound Notification - Claude Code Hook (Windows)
# Plays sound when Claude Code task completes or asks for permission

try {
    $soundPath = "C:\Windows\Media\notify.wav"
    if (Test-Path $soundPath) {
        (New-Object Media.SoundPlayer $soundPath).PlaySync()
    }
} catch {
    # Silently ignore errors - notification is non-critical
}
exit 0
