# Axiom Phase 3 Master Import
# This script imports all Phase 3 workflows into the live n8n instance.

$PROJECT_ROOT = $PSScriptRoot
if (-not $PROJECT_ROOT) { $PROJECT_ROOT = (Get-Location).Path }

Write-Host "--- Axiom Nexus: Phase 3 Activation ---" -ForegroundColor Cyan

$workflows = @(
    "Axiom-Master-Router.json",
    "Axiom-Invoice-Processor.json",
    "Axiom-Auto-Filer.json"
)

foreach ($wf in $workflows) {
    $fullPath = Join-Path $PROJECT_ROOT $wf
    if (Test-Path $fullPath) {
        Write-Host "Importing $wf..." -ForegroundColor Yellow
        # We use n8n CLI to import. Note: n8n must be in Path or fully qualified.
        # This assumes the managed stack naming convention.
        n8n import:workflow --input="$fullPath"
    }
    else {
        Write-Warning "Could not find $wf at $fullPath"
    }
}

Write-Host "--- Phase 3 Activation Complete ---" -ForegroundColor Green
Write-Host "The Axiom Hub is now fully connected to the Master Router Engine."
