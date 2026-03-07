# ==============================================================================
# Axiom Nexus - Stack Launcher
# This script starts the n8n background engine with v2 robustness.
# ==============================================================================

Add-Type -AssemblyName System.Windows.Forms
Set-Location -Path $PSScriptRoot

# 1. Force Cleanup of Ghost Processes
# n8n v2 can leave "zombie" node processes that hold the port but don't serve the UI.
Write-Host "Clearing legacy state..." -ForegroundColor Gray
Get-Process -Name "node", "n8n" -ErrorAction SilentlyContinue | Where-Object { 
    $p = $_
    try {
        $c = Get-NetTCPConnection -LocalPort 5678 -OwningProcess $p.Id -ErrorAction SilentlyContinue
        $null -ne $c
    }
    catch { $false }
} | Stop-Process -Force -ErrorAction SilentlyContinue

# 2. Start Engine
$env:N8N_PORT = 5678
# Shielding against Windows DB permission quirks in v2
$env:N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "false"

# We avoid setting N8N_HOST/PROTOCOL to allow n8n to auto-detect the UI routes correctly
$env:N8N_DIAGNOSTICS_ENABLED = "false"
$env:N8N_VERSION_NOTIFICATIONS_ENABLED = "false"

# Load the custom node directly from the local disk, bypassing the community node npm registry
$customNodePath = Resolve-Path (Join-Path $PSScriptRoot "..\n8n-nodes-local-ai-manager")
$env:N8N_CUSTOM_EXTENSIONS = $customNodePath.Path

Write-Host "Initializing Axiom Nexus Engine..." -ForegroundColor Cyan
Start-Process cmd.exe -ArgumentList "/c n8n start" -WindowStyle Hidden

# 3. Verify Health (Not just the port)
$maxRetries = 40
$retryCount = 0
$isStarted = $false
$healthUrl = "http://localhost:5678/healthz"

while (-not $isStarted -and $retryCount -lt $maxRetries) {
    try {
        $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
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
    [System.Windows.Forms.MessageBox]::Show("The Axiom Nexus engine failed to serve the dashboard within 40 seconds. Check if another app is using port 5678.", "Startup Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
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
