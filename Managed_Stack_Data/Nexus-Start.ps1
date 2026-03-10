# ==============================================================================
# Axiom Nexus - Stack Launcher
# This script starts the n8n background engine with v2 robustness.
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Set-Location -Path $PSScriptRoot
$script:n8nProcessId = $null

# Keep npm/node stderr notices from being surfaced as terminating PowerShell errors.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    [System.Windows.Forms.MessageBox]::Show(
        "Axiom Nexus launcher must run as Administrator for reliable restart/port cleanup. Please re-open using 'Run as administrator'.",
        "Axiom Nexus",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit
}

function Test-N8nReady {
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:5678/healthz" -TimeoutSec 2 -ErrorAction Stop
        return $resp.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Stop-ProcessTreeById {
    param(
        [int]$ProcessId
    )

    if ($ProcessId -le 0) { return }
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }

    & taskkill /F /PID $ProcessId /T 2>&1 | Out-Null
}

function Stop-ListenersOnPorts {
    param(
        [int[]]$Ports
    )

    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($port in $Ports) {
        try {
            $listeners = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            foreach ($c in $listeners) {
                if ($c -and $c.OwningProcess -and $c.OwningProcess -gt 0) {
                    [void]$pids.Add([int]$c.OwningProcess)
                }
            }
        }
        catch { }
    }

    foreach ($pid in $pids) {
        Stop-ProcessTreeById -ProcessId $pid
    }
}

function Wait-PortsReleased {
    param(
        [int[]]$Ports,
        [int]$TimeoutSeconds = 12
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $busy = $false
        foreach ($port in $Ports) {
            if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
                $busy = $true
                break
            }
        }
        if (-not $busy) { return $true }
        Start-Sleep -Milliseconds 400
    }

    return $false
}

function Stop-AxiomStack {
    if ($script:n8nProcessId) {
        Stop-ProcessTreeById -ProcessId $script:n8nProcessId
        $script:n8nProcessId = $null
    }

    Stop-ListenersOnPorts -Ports @(5678, 5679)
    Get-Process -Name "node", "n8n" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    [void](Wait-PortsReleased -Ports @(5678, 5679))
}

function Sync-CustomNodePackage {
    param(
        [string]$RootDir
    )

    $tarball = $null
    $sourcePkgDir = Join-Path (Split-Path $RootDir -Parent) "n8n-nodes-local-ai-manager"
    $sourceBuildAttempted = $false
    $sourceBuildFailed = $false
    if (Test-Path (Join-Path $sourcePkgDir "package.json")) {
        $sourceBuildAttempted = $true
        Write-Host "Building local custom node package from source..." -ForegroundColor Gray
        Push-Location $sourcePkgDir
        try {
            & npm run build | Out-Null
            if ($LASTEXITCODE -eq 0) {
                & npm pack | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $builtTarball = Get-ChildItem -Path $sourcePkgDir -Filter "n8n-nodes-local-ai-manager-*.tgz" -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1
                    if ($builtTarball) {
                        $copiedTarball = Join-Path $RootDir $builtTarball.Name
                        Copy-Item -Path $builtTarball.FullName -Destination $copiedTarball -Force
                        $tarball = $copiedTarball
                        Write-Host "Updated package tarball: $($builtTarball.Name)" -ForegroundColor Gray
                    }
                }
                else {
                    Write-Host "ERROR: npm pack failed with exit code $LASTEXITCODE" -ForegroundColor Red
                    $sourceBuildFailed = $true
                }
            }
            else {
                Write-Host "ERROR: npm run build failed with exit code $LASTEXITCODE" -ForegroundColor Red
                $sourceBuildFailed = $true
            }
        }
        catch {
            Write-Host "ERROR: Source package build failed: $($_.Exception.Message)" -ForegroundColor Red
            $sourceBuildFailed = $true
        }
        finally {
            Pop-Location
        }
    }

    if ($sourceBuildAttempted -and $sourceBuildFailed) {
        Write-Host "ERROR: Aborting startup to avoid loading stale custom node package." -ForegroundColor Red
        return $false
    }

    if (-not $tarball) {
        $tarballs = Get-ChildItem -Path $RootDir -Filter "n8n-nodes-local-ai-manager-*.tgz" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        if ($tarballs -and $tarballs.Count -gt 0) {
            $tarball = $tarballs[0].FullName
        }
    }
    if (-not $tarball) {
        Write-Host "WARNING: No custom node package tarball found in $RootDir" -ForegroundColor Yellow
        return $false
    }

    $nodesDir = Join-Path $env:USERPROFILE ".n8n\nodes"
    New-Item -Path $nodesDir -ItemType Directory -Force | Out-Null

    $pkgJsonPath = Join-Path $nodesDir "package.json"
    if (-not (Test-Path $pkgJsonPath)) {
        $bootstrap = @{
            name = "installed-nodes"
            private = $true
            dependencies = @{}
        } | ConvertTo-Json -Depth 6
        Set-Content -Path $pkgJsonPath -Value $bootstrap -Encoding UTF8
    }

    Write-Host "Syncing custom node package: $([System.IO.Path]::GetFileName($tarball))" -ForegroundColor Gray
    Push-Location $nodesDir
    try {
        & npm install --force "file:$tarball" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: npm install failed with exit code $LASTEXITCODE" -ForegroundColor Red
            return $false
        }
    }
    finally {
        Pop-Location
    }

    $parserPath = Join-Path $nodesDir "node_modules\n8n-nodes-local-ai-manager\dist\lib\axiomParser.js"
    if (-not (Test-Path $parserPath)) {
        Write-Host "ERROR: axiomParser.js missing after package sync." -ForegroundColor Red
        return $false
    }

    try {
        $pkgPath = Join-Path $nodesDir "node_modules\n8n-nodes-local-ai-manager\package.json"
        $pkgVersion = if (Test-Path $pkgPath) { (Get-Content $pkgPath -Raw | ConvertFrom-Json).version } else { "unknown" }
        $parserHash = (Get-FileHash -Path $parserPath -Algorithm SHA256).Hash.Substring(0, 12)
        Write-Host "Installed custom node version: $pkgVersion (parser sha256:$parserHash)" -ForegroundColor Gray
    }
    catch {
        Write-Host "WARNING: Could not compute parser fingerprint: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    return $true
}

# 1. Force cleanup before every start
Write-Host "Clearing legacy state..." -ForegroundColor Gray
Stop-AxiomStack

# 2. Start Engine
$env:N8N_PORT = 5678
# Shielding against Windows DB permission quirks in v2
$env:N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "false"

# We avoid setting N8N_HOST/PROTOCOL to allow n8n to auto-detect the UI routes correctly
$env:N8N_DIAGNOSTICS_ENABLED = "false"
$env:N8N_VERSION_NOTIFICATIONS_ENABLED = "false"
$env:NODE_FUNCTION_ALLOW_BUILTIN = "fs,path"

if (-not (Sync-CustomNodePackage -RootDir $PSScriptRoot)) {
    [System.Windows.Forms.MessageBox]::Show("Custom node sync failed. Engine startup aborted to prevent stale runtime.", "Axiom Nexus", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    exit
}

if (Test-Path (Join-Path $PSScriptRoot "Axiom-Master-Router.json")) {
    Write-Host "Importing latest Axiom Master Router..." -ForegroundColor Gray
    & n8n import:workflow --input=(Join-Path $PSScriptRoot "Axiom-Master-Router.json") | Out-Null
}
Write-Host "Publishing router workflow..." -ForegroundColor Gray
& n8n publish:workflow --id=dTzRbVa8bRBZTZ6O | Out-Null

Write-Host "Initializing Axiom Nexus Engine..." -ForegroundColor Cyan
$bootLog = Join-Path $env:TEMP ("axiom_boot_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss_fff"))
$n8nProc = Start-Process cmd.exe -ArgumentList "/c chcp 65001 > NUL && n8n start > `"$bootLog`" 2>&1" -WindowStyle Hidden -PassThru
if ($n8nProc) {
    $script:n8nProcessId = $n8nProc.Id
    Write-Host "Started n8n host process PID $($script:n8nProcessId)" -ForegroundColor Gray
}

# 3. Verify Health (Not just the port)
$maxRetries = 40
$retryCount = 0
$isStarted = $false
$healthUrl = "http://localhost:5678/healthz"

while (-not $isStarted -and $retryCount -lt $maxRetries) {
    if ($script:n8nProcessId -and -not (Get-Process -Id $script:n8nProcessId -ErrorAction SilentlyContinue)) {
        break
    }
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $isStarted = $true
        }
    }
    catch {
        $retryCount++
        Start-Sleep -Seconds 1
    }
}

# 4. Open Dashboard
if ($isStarted) {
    # Verify assets before opening
    $npmRoot = try { Invoke-Expression "npm root -g" | Out-String } catch { $null }
    $n8nPath = if ($npmRoot) { Join-Path $npmRoot.Trim() "n8n" } else { "$env:APPDATA\npm\node_modules\n8n" }
    $uiAsset = Join-Path $n8nPath "dist\public\index.html"

    if (-not (Test-Path $uiAsset)) {
        [System.Windows.Forms.MessageBox]::Show("CRITICAL ERROR: n8n UI assets are missing (Cannot GET /). Please run the Axiom Nexus Installer and select 'Install' to repair.", "UI Integrity Failure", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
        exit
    }

    # Extra second to allow routes to fully register
    Start-Sleep -Seconds 1
    Write-Host "Engine Ready. Opening Dashboard..." -ForegroundColor Green
    Start-Process "http://localhost:5678"
}
else {
    Stop-AxiomStack
    [System.Windows.Forms.MessageBox]::Show("The Axiom Nexus engine failed to become healthy within 40 seconds. Boot log: $bootLog", "Startup Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
}

exit

# SIG # Begin signature block
# MIIFdgYJKoZIhvcNAQcCoIIFZzCCBWMCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUPO5/Adabjf35RhcPFyPom1tH
# a7ugggMOMIIDCjCCAfKgAwIBAgIQE0cy1VHaN7tJftbFBRHhijANBgkqhkiG9w0B
# AQsFADAdMRswGQYDVQQDDBJBeGlvbS1OZXh1cy1TZWN1cmUwHhcNMjYwMzA1MjEy
# MDUyWhcNMjcwMzA1MjE0MDUyWjAdMRswGQYDVQQDDBJBeGlvbS1OZXh1cy1TZWN1
# cmUwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDqthNyYGdxkdmOfloS
# BlsgQKXE1YUDr5Qt7ZmWqr44BLsK4UNu1E+Sa6yv1aIdX5VKW4HCIurfkj8pmS50
# /sw79nrf4FYv2DStHHgJU9pW3L8aTkk16HQxXD/VV0EmiRAz7Fznx+W6JyEq5+pX
# bSPAKJQY6SPX4AYrD7RibX/iclwae3DlWJNMfQyBLVIU1Y/yRPj0MmdHKqZtDIAW
# yIlZCtCJPt36NP56t62uZHoKqN7xhEKV5gjYGgh+PMaXbUWd4DVRgLxp374WOYnv
# NgoTeOnp3pNQhrLvvL5jZaDR+8+VpBP9f4S/aQwhBRS9BHL3qP8MvyeH+hfhZAhX
# RiHRAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcD
# AzAdBgNVHQ4EFgQUwsY5BjSAI3Wh23HaPCmkfermHZ4wDQYJKoZIhvcNAQELBQAD
# ggEBABe7/poRzLR48vr1vtN5xhKWNmHQw08WbHOk4fm5S5lv1z6MyWKTodgM6W2J
# TmM3/kXneiIPfybXdA2TCtbNO0exEC0sqoTnxvss+iHhj93YdqGhyUtvxmbpQJjK
# V6mtqqmj65GUAbJWT2bQeO2m6ZYudxZ2UyfNr26daaAIPUIvoH45e6+4tS4QiIFb
# pw950At1hpXaGHZMOv3DAgXPg08eCMCYFmC5kwIQ2YUj6UMa/laYFJTGUCOBiJwy
# zuZj9xf0aE66F+Hf8s0s3s0Ro21OTCqAfNV8TwAsKzgSX/yA43/rxFVfblemD35z
# puqmoiRfDAsXqB+QBF8H445DapMxggHSMIIBzgIBATAxMB0xGzAZBgNVBAMMEkF4
# aW9tLU5leHVzLVNlY3VyZQIQE0cy1VHaN7tJftbFBRHhijAJBgUrDgMCGgUAoHgw
# GAYKKwYBBAGCNwIBDDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGC
# NwIBBDAcBgorBgEEAYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQx
# FgQUfIoh5ylJZpZ3I1NWo1hERHhP0dYwDQYJKoZIhvcNAQEBBQAEggEAzxz5Dkhz
# duF92uAjjci6PIS1uZpG7fwPvSIUqCy+rup5ozs39/yXpSjuGwFl/m61wR0LEx6u
# rx6CbZKhHox3D18CnjkswGyVLs6WEqCHOVmjV+Bx1HvrIN2LjYUQgslWYwS1KqqS
# aiFjx1+7DkPCmQfpzTIrai/ogBszt3Ntw36krySCUWRVNhkHkjt5+1XNpxc17Hcn
# cXeleoS5Zdjmge0iQZf91ow1qthWuhWQ9Weabeqpdul0t9CHGGoIlznDv0tV5xqc
# 7yQ7F8IyZtpVCX3/DRp7T3QxAjPcsP5IFNLjD/CM3viscY2zwfxavEicMDN1sI/v
# XoGGLtWWxS0ouA==
# SIG # End signature block
