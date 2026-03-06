$sh = New-Object -ComObject WScript.Shell
$basePath = (Get-Location).Path
$psPath = "powershell.exe"

$shortcuts = @(
    @{
        LinkPath   = Join-Path $basePath "Install Axiom Nexus.lnk"
        TargetPath = $psPath
        Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$basePath\Managed_Stack_Data\INSTALL-AXIOM-ENGINE.ps1`""
        Icon       = "$psPath, 0"
    },
    @{
        LinkPath   = Join-Path $basePath "Launch Axiom Nexus.lnk"
        TargetPath = $psPath
        Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$basePath\Managed_Stack_Data\LAUNCH-GUI.ps1`""
        Icon       = "$psPath, 0"
    },
    @{
        LinkPath   = Join-Path $basePath "Uninstall Axiom Nexus.lnk"
        TargetPath = $psPath
        Arguments  = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$basePath\UNINSTALL-GUI.ps1`""
        Icon       = "$psPath, 0"
    }
)

foreach ($s in $shortcuts) {
    if (Test-Path $s.LinkPath) { Remove-Item $s.LinkPath -Force }
    $lnk = $sh.CreateShortcut($s.LinkPath)
    $lnk.TargetPath = $s.TargetPath
    $lnk.Arguments = $s.Arguments
    $lnk.IconLocation = $s.Icon
    $lnk.Save()

    # Apply byte patch 0x15 to bit 5 to require Administrator
    $bytes = [System.IO.File]::ReadAllBytes($s.LinkPath)
    $bytes[0x15] = $bytes[0x15] -bor 0x20
    [System.IO.File]::WriteAllBytes($s.LinkPath, $bytes)
}
Write-Host "Rebuilt shortcuts with icons!"
