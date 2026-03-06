# ==============================================================================
# Axiom Nexus - Digital Signature Pipeline
# Generates a self-signed certificate and applies it to all suite scripts.
# ==============================================================================

$certName = "Axiom-Nexus-Secure"
$cert = Get-ChildItem -Path Cert:\CurrentUser\My | Where-Object { $_.Subject -match $certName } | Select-Object -First 1

if (-not $cert) {
    Write-Host "Generating New Self-Signed Certificate: $certName..." -ForegroundColor Cyan
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=$certName" -CertStoreLocation Cert:\CurrentUser\My
}

$scripts = Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" | Where-Object {
    $_.Name -match "LAUNCH-GUI.ps1" -or 
    $_.Name -match "INSTALL-AXIOM-ENGINE.ps1" -or 
    $_.Name -match "UNINSTALL-GUI.ps1" -or
    $_.Name -match "Nexus-Start.ps1" -or
    $_.Name -match "Nexus-Uninstaller.ps1" -or
    $_.Name -match "Sign-Scripts.ps1"
}
foreach ($script in $scripts) {
    Write-Host "Signing: $($script.Name)..." -ForegroundColor Green
    Set-AuthenticodeSignature -FilePath $script.FullName -Certificate $cert | Out-Null
}

Write-Host "All scripts signed successfully with $certName."

# SIG # Begin signature block
# MIIFdgYJKoZIhvcNAQcCoIIFZzCCBWMCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUjGx44LIYPl5gl4aR8qTibAdC
# B1SgggMOMIIDCjCCAfKgAwIBAgIQE0cy1VHaN7tJftbFBRHhijANBgkqhkiG9w0B
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
# FgQUZftJA5/anuxdNU/T9BpHUwpcI94wDQYJKoZIhvcNAQEBBQAEggEAirqoIbZw
# vMggo4+TmSELLYsQ3gXWD/GL1lSkDzztc+lTdLHhC5c8VyvsZCw0QH/6amNgZQc8
# aKDlmR3Gii6s8E2ACdK0w/51a4Xy0t4PhQn+fD4KT8ibA9aaxchuzFo+mxBl+w//
# KCRziHSvvcOoxnTgFtKd+wQXEYjuLgia6Flw4lLLDKw6KyVzWjh4e5koSptT7kzk
# 8edlEjEjU4r3Yfp6LOxf0OHXwj2wohQ0HSgJq6GPs/fblBll2ya8V+XUAd1azb+U
# 5UwCyjMC4K6Hs0OrlipGJIBua8LjEvRBF4NOUj2hpssLecUUCe+FcL3nY5TTKpc8
# ywqgH0OZr6118w==
# SIG # End signature block
