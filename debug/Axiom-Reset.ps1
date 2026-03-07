<#
.SYNOPSIS
    Axiom-Reset: Emergency UI Rollback Switch
.DESCRIPTION
    This script provides an emergency "Panic Button" for the Axiom Hub.
    If the Recursive Architect (AI) creates an infinite loop or breaks the React DOM 
    during self-evolution, this script enforces a hard git checkout to restore the UI.
#>

$SourceDir = "C:\Axiom_Source\src"
$TargetFile = "$SourceDir\App.tsx"

Write-Host "===========================" -ForegroundColor Red
Write-Host " AXIOM EMERGENCY ROLLBACK  " -ForegroundColor Red
Write-Host "===========================" -ForegroundColor Red
Write-Host ""
Write-Host "WARNING: This will destroy all current UI modifications" -ForegroundColor Yellow
Write-Host "made by the Recursive Architect and restore the baseline App.tsx." -ForegroundColor Yellow
Write-Host ""

$confirm = Read-Host "Type 'RESTORE' to proceed"

if ($confirm -ceq "RESTORE") {
    Write-Host "`nInitiating Git Hard Reset for App.tsx..." -ForegroundColor Cyan
    
    if (Test-Path $SourceDir) {
        Set-Location $SourceDir
        
        # Check if it's a git repo
        if (Test-Path ".git") {
            try {
                git checkout -- App.tsx
                Write-Host "[SUCCESS] UI DOM Restored to last stable commit." -ForegroundColor Green
            }
            catch {
                Write-Host "[ERROR] Git checkout failed. Searching for .bak file..." -ForegroundColor Red
                if (Test-Path "$TargetFile.bak") {
                    Copy-Item -Path "$TargetFile.bak" -Destination $TargetFile -Force
                    Write-Host "[SUCCESS] Restored from local App.tsx.bak" -ForegroundColor Green
                }
                else {
                    Write-Host "[FATAL] No backup found. Manual intervention required." -ForegroundColor Red
                }
            }
        }
        else {
            Write-Host "[WARNING] Not a Git repository. Attempting .bak restore..." -ForegroundColor Yellow
            if (Test-Path "$TargetFile.bak") {
                Copy-Item -Path "$TargetFile.bak" -Destination $TargetFile -Force
                Write-Host "[SUCCESS] Restored from local App.tsx.bak" -ForegroundColor Green
            }
            else {
                Write-Host "[FATAL] No backup found. Manual intervention required." -ForegroundColor Red
            }
        }
        
        Write-Host "`nPlease restart the Axiom Hub to apply changes." -ForegroundColor Cyan
    }
    else {
        Write-Host "[ERROR] Source directory not found: $SourceDir" -ForegroundColor Red
    }
}
else {
    Write-Host "`nRollback aborted." -ForegroundColor Green
}

Write-Host "`nPress any key to exit..."
$Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
