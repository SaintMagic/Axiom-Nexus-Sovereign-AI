Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type -AssemblyName System.Drawing

# --- SELF-HIDING CONSOLE LOGIC ---
$code = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32" -ErrorAction SilentlyContinue
$hwnd = (Get-Process -Id $PID).MainWindowHandle
if ($hwnd -ne [IntPtr]::Zero) { [Win32.Win32ShowWindow]::ShowWindow($hwnd, 0) }

# --- INITIALIZATION ---
$logFile = Join-Path $env:TEMP "axiom_boot.log"
if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }
" " | Out-File $logFile -Encoding utf8 -Force
$lastFileSize = 0

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Axiom Launch Center"
$form.Size = New-Object System.Drawing.Size(600, 480)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Logo Implementation
$logoPath = Join-Path $PSScriptRoot "Axiom Nexus Logo.jpg"
if (Test-Path $logoPath) {
    $pictureBox = New-Object System.Windows.Forms.PictureBox
    $pictureBox.Image = [System.Drawing.Image]::FromFile($logoPath)
    $pictureBox.Size = New-Object System.Drawing.Size(70, 70)
    $pictureBox.Location = New-Object System.Drawing.Point(20, 20)
    $pictureBox.SizeMode = "Zoom"
    $form.Controls.Add($pictureBox)
}

# Title Label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Axiom Launch Center"
$titleLabel.AutoSize = $true
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(110, 25)
$form.Controls.Add($titleLabel)

# Status Label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Initializing Axiom Nexus Engine..."
$statusLabel.Size = New-Object System.Drawing.Size(440, 25)
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$statusLabel.Location = New-Object System.Drawing.Point(110, 55)
$form.Controls.Add($statusLabel)

# Terminal Output Box
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Size = New-Object System.Drawing.Size(540, 260)
$textBox.Location = New-Object System.Drawing.Point(20, 100)
$textBox.Multiline = $true
$textBox.ReadOnly = $true
$textBox.ScrollBars = "Vertical"
$textBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$textBox.BackColor = [System.Drawing.Color]::Black
$textBox.ForeColor = [System.Drawing.Color]::LightGray
$form.Controls.Add($textBox)

# Verification Timer
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500

$timer.Add_Tick({
        if (Test-Path $logFile) {
            try {
                $info = New-Object System.IO.FileInfo($logFile)
                if ($info.Length -gt $lastFileSize) {
                    $fs = New-Object System.IO.FileStream($logFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $fs.Seek($lastFileSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                    $newData = $sr.ReadToEnd()
                    $sr.Close(); $fs.Close()
                    $script:lastFileSize = $info.Length
                
                    if ($newData) {
                        $textBox.AppendText($newData)
                        $textBox.SelectionStart = $textBox.TextLength
                        $textBox.ScrollToCaret()
                    
                        if ($newData -like "*localhost:5678*") {
                            $timer.Stop()
                            $statusLabel.Text = "Axiom Engine Ready. Launching Hub..."
                            $statusLabel.ForeColor = [System.Drawing.Color]::Green
                            
                            # --- THE AXIOM HUB LAUNCH PROTOCOL ---
                            try {
                                $hubPath = (Get-Item (Join-Path $PSScriptRoot "Axiom-Hub.html")).FullName
                                $hubUrl = "file:///" + $hubPath.Replace("\", "/")
                                Start-Process "msedge.exe" -ArgumentList "--app=`"$hubUrl`"", "--new-window" -ErrorAction Stop
                            }
                            catch {
                                # Fallback to default browser if msedge isn't found
                                $hubPath = Join-Path $PSScriptRoot "Axiom-Hub.html"
                                Start-Process $hubPath
                            }
                            
                            Start-Sleep -Seconds 2
                            $form.Close()
                        }
                    }
                }
            }
            catch { }
        }
    })

$form.Add_Shown({
        # Step 1: Silent Process Cleanup
        $textBox.AppendText("--- Clearing Lingering AI Processes ---`r`n")
        $procs = @("node", "n8n", "ollama", "ollama app")
        foreach ($p in $procs) {
            if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
                $textBox.AppendText("Closing $p...`r`n")
                taskkill /F /IM "$p.exe" /T 2>$null | Out-Null
            }
        }
    
        # Step 2: Start n8n background (Optimized)
        $textBox.AppendText("--- Booting Autonomous Engine ---`r`n")
        $env:N8N_BLOCK_PYTHON_SANDBOX_TASKS = "true"
        $env:N8N_SKIP_WEBHOOK_DEREGISTRATION_ON_SHUTDOWN = "true"
        $env:WEBHOOK_URL = "http://localhost:5678/"
        $env:N8N_CORS_ALLOWED_ORIGINS = "*"
        $env:N8N_CORS_ALLOWED_HEADERS = "*"
        
        # Disable auto-update checks and analytics that might trigger npm lookups
        $env:N8N_DIAGNOSTICS_ENABLED = "false"
        $env:N8N_VERSION_NOTIFICATIONS_ENABLED = "false"
        
        Start-Process cmd.exe -ArgumentList "/c chcp 65001 > NUL && n8n start > `"$logFile`" 2>&1" -WindowStyle Hidden
    
        $timer.Start()
    })

$form.ShowDialog() | Out-Null

# SIG # Begin signature block
# MIIFdgYJKoZIhvcNAQcCoIIFZzCCBWMCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUnlK2g/tacRCDzJpvLIMB3AYv
# y9SgggMOMIIDCjCCAfKgAwIBAgIQE0cy1VHaN7tJftbFBRHhijANBgkqhkiG9w0B
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
# FgQUBPhcxzLT/z8qUK33TmJ9IDtjVlkwDQYJKoZIhvcNAQEBBQAEggEATsrEbMH2
# CvjKVDlmOw1Lhh1FDSz3YZUbPoPOC4ll5GKiGBWDfoqE0lvHPtewQ5v5pG5u9bX+
# sCaKHt9L0xTO47NvfZjYbkDvVyTkuHepdY549JsmMfi58NbaX0rpgB3fcPFg83Fx
# I649aOP0s0pPVPEdS7+ioAMbPvzWUt+vGD19hvRXpB/jXQV8GXi4bof4RZcZqJMf
# yPzmaAi5y1pV1ZkAsb8x//w6Y2VzG2/pmT//rDE25KPvzWbfwieH9Wfflzg/zZ8w
# wbOY2sIRVTg3duXqwFHuDqwv1C9gRpHxrA3+AZ5pAoYZKyg4zqIGenPVjDUH+9VN
# KmmizYeVi1niiA==
# SIG # End signature block
