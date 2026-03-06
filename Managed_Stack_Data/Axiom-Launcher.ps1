# ==============================================================================
# Managed AI Agent Stack - Installer Launcher
# ==============================================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    $elevateArgs = @(
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        "`"$PSCommandPath`""
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $elevateArgs -Verb RunAs
    exit
}

Set-Location -Path $PSScriptRoot
& ".\INSTALL-NEXUS.ps1"
exit

# SIG # Begin signature block
# MIIFdgYJKoZIhvcNAQcCoIIFZzCCBWMCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU+/c5iSGlWL1/293gDQjfA0eq
# 4NegggMOMIIDCjCCAfKgAwIBAgIQE0cy1VHaN7tJftbFBRHhijANBgkqhkiG9w0B
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
# FgQUJqaMjBP75CgUt8EpVxRQ7IB3gbgwDQYJKoZIhvcNAQEBBQAEggEAYZ3Ry5xw
# k6sCX+ORxghxbL++ApYZkwzgPxfTEs8pWfyUglpmOf4tDfYbSeEio2lqAUq0KqRe
# ulvxcM39OC/DBvMa0sVr+MXqPsfINKyezLdVL1uAMEFXozoSukUiGVhbe4vOWNdq
# 2xjTEDo7U5B96WF+TeOoV5COAv1i7Lt4s9wbY3s2hgP6q9A+HwBbvPih1Rtew0Rq
# dp/qm/UiJjDCatAbdc3OItyK9kYS+9/x2hRrGXnM5QAEVmVbrwJ92KuguRwqbCIB
# 1qdzYepUvEzbodty0NK/2CuDmcF5bBXBaCgMMvSLFU/jmyazOp5JK4Ds1bISeu52
# lkk1vNDYKo/MZQ==
# SIG # End signature block
