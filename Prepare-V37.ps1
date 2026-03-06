# Master Patch V37
$base = (Get-Location).Path
$data = Join-Path $base "Managed_Stack_Data"

# 1. Update Sign-Scripts.ps1
$signPath = Join-Path $data "Sign-Scripts.ps1"
$content = Get-Content $signPath
$newContent = $content -replace "INSTALL-GUI.ps1", "INSTALL-AXIOM-ENGINE.ps1"
Set-Content $signPath $newContent -Encoding UTF8

# 2. Run Shortcuts
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\native-shortcuts.ps1"

# 3. Run Sign
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $signPath

Write-Host "V37 Preparation Complete."
