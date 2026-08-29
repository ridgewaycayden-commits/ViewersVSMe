Set-Location $PSScriptRoot

Write-Host "ViewersVSMe auto-pull is running."
Write-Host "Checking GitHub every 3 seconds. Press Ctrl+C to stop."

while ($true) {
    git pull --ff-only
    Start-Sleep -Seconds 3
}
