# Axiom Phase 3 Master Import
# This script imports all Phase 3 workflows into the live n8n instance.

$PROJECT_ROOT = $PSScriptRoot
if (-not $PROJECT_ROOT) { $PROJECT_ROOT = (Get-Location).Path }

Write-Host "[4/4] Installing Axiom Custom Nodes (Sovereign Node Protocol V7)..." -ForegroundColor Cyan
$customNodeSource = Join-Path $PSScriptRoot "n8n-nodes-local-ai-manager"
$n8nNodesDir = Join-Path $env:USERPROFILE ".n8n\nodes"

# Ensure root nodes directory exists
if (-not (Test-Path $n8nNodesDir)) {
    New-Item -ItemType Directory -Path $n8nNodesDir -Force | Out-Null
}

try {
    # The V7 "True Root Cause" Fix: Don't just copy files, actually install them via npm
    # so n8n's backend registry detects the dependency in package.json
    Write-Host "      Compiling local node..." -ForegroundColor Gray
    Push-Location $customNodeSource
    npm run build | Out-Null
    Pop-Location

    Write-Host "      Executing native npm installation into n8n registry..." -ForegroundColor Gray
    Push-Location $n8nNodesDir
    npm install "$customNodeSource" --no-fund --no-audit | Out-Null
    Pop-Location

    Write-Host "      Custom nodes installed and registered successfully." -ForegroundColor Green
}
catch {
    Write-Host "      [WARNING] Custom node installation failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
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
