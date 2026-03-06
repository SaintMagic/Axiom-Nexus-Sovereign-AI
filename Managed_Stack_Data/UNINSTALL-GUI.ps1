Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$logFile = "$env:USERPROFILE\Desktop\Axiom-Nexus-Uninstall-Log.txt"
if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }

# --- SHARED-STREAM LOGGING HELPER ---
function Write-Log {
    param([string]$Message)
    try {
        $msg = "[$(Get-Date -Format 'HH:mm:ss')] $Message`r`n"
        [System.IO.File]::AppendAllText($logFile, $msg)
    }
    catch { }
}


# --- SELF-HIDING CONSOLE LOGIC ---
$code = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32" -ErrorAction SilentlyContinue
$hwnd = (Get-Process -Id $PID).MainWindowHandle
if ($hwnd -ne [IntPtr]::Zero) { [Win32.Win32ShowWindow]::ShowWindow($hwnd, 0) } # 0 = SW_HIDE


# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Axiom Nexus: Sovereign AI Suite"
$form.Size = New-Object System.Drawing.Size(600, 500)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Logo Implementation
$logoPath = Join-Path $PSScriptRoot "Axiom Nexus Logo.jpg"
if (Test-Path $logoPath) {
    $pictureBox = New-Object System.Windows.Forms.PictureBox
    $pictureBox.Image = [System.Drawing.Image]::FromFile($logoPath)
    $pictureBox.Size = New-Object System.Drawing.Size(80, 80)
    $pictureBox.Location = New-Object System.Drawing.Point(20, 20)
    $pictureBox.SizeMode = "Zoom"
    $form.Controls.Add($pictureBox)
}

# Title Label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = "Axiom Nexus Cleanup"
$titleLabel.AutoSize = $true
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(120, 25)
$form.Controls.Add($titleLabel)

# Status Label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Axiom Nexus: Sovereign AI Suite"
$statusLabel.Size = New-Object System.Drawing.Size(440, 30)
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$statusLabel.Location = New-Object System.Drawing.Point(120, 60)
$form.Controls.Add($statusLabel)

# Progress Bar (Red Marquee simulation via continuous red)
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size = New-Object System.Drawing.Size(540, 30)
$progressBar.Location = New-Object System.Drawing.Point(20, 110)
$progressBar.Style = "Marquee"
$progressBar.MarqueeAnimationSpeed = 30
$progressBar.ForeColor = [System.Drawing.Color]::Firebrick
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$form.Controls.Add($progressBar)

# Terminal Output Box
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Size = New-Object System.Drawing.Size(540, 200)
$textBox.Location = New-Object System.Drawing.Point(20, 160)
$textBox.Multiline = $true
$textBox.ReadOnly = $true
$textBox.ScrollBars = "Vertical"
$textBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$textBox.BackColor = [System.Drawing.Color]::Maroon
$textBox.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($textBox)

# Uninstall Button
$uninstallButton = New-Object System.Windows.Forms.Button
$uninstallButton.Text = "Remove Managed Stack"
$uninstallButton.Size = New-Object System.Drawing.Size(200, 45)
$uninstallButton.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$uninstallButton.Location = New-Object System.Drawing.Point(190, 380)
$form.Controls.Add($uninstallButton)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300

function Update-TextBox {
    if (Test-Path $logFile) {
        try {
            $info = New-Object System.IO.FileInfo($logFile)
            if ($info.Length -gt $global:lastFileSize) {
                $fs = New-Object System.IO.FileStream($logFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $fs.Seek($global:lastFileSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                $sr = New-Object System.IO.StreamReader($fs)
                $newData = $sr.ReadToEnd()
                $sr.Close()
                $fs.Close()
                $global:lastFileSize = $info.Length
                if ($newData) { 
                    $incomingLines = $newData -split "`n"
                    $cleanData = ""
                    # Robust ANSI escape sequence filter
                    $ansiRegex = "\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
                    foreach ($line in $incomingLines) {
                        $stripped = $line -replace $ansiRegex, ""
                        if ($stripped -notmatch "██|▒▒|npm warn") { $cleanData += $stripped + "`n" }
                    }
                    if ($cleanData.Trim() -ne "") { $textBox.AppendText($cleanData) }
                }
            }
        }
        catch { }
    }
}

function Start-NextStep {
    try {
        if ($global:installStep -eq 1) {
            $statusLabel.Text = "Step 1/4: Removing Node Modules (n8n, OpenClaw)..."
            $progressBar.Value = 25
            Write-Log "--- Uninstalling Global Packages ---"
            $global:installProcess = Start-Process cmd.exe -ArgumentList "/c npm uninstall -g n8n openclaw --no-progress >> `"$logFile`" 2>&1" -WindowStyle Hidden -PassThru
        }
        elseif ($global:installStep -eq 2) {
            $statusLabel.Text = "Step 2/4: Removing Ollama Core..."
            $progressBar.Value = 50
            Write-Log "--- Uninstalling Ollama ---"
            $global:installProcess = Start-Process cmd.exe -ArgumentList "/c winget uninstall --id Ollama.Ollama --silent --disable-interactivity >> `"$logFile`" 2>&1" -WindowStyle Hidden -PassThru
        }
        elseif ($global:installStep -eq 3) {
            $statusLabel.Text = "Step 3/4: Removing Node.js..."
            $progressBar.Value = 75
            Write-Log "--- Uninstalling Node.js ---"
            $global:installProcess = Start-Process cmd.exe -ArgumentList "/c winget uninstall --id OpenJS.NodeJS --silent --disable-interactivity >> `"$logFile`" 2>&1" -WindowStyle Hidden -PassThru
        }
        elseif ($global:installStep -eq 4) {
            $statusLabel.Text = "Step 4/4: Wiping local configuration files..."
            $progressBar.Value = 90
            Write-Log "--- Wiping .n8n and .openclaw directories ---"
            $n8nDir = "$env:USERPROFILE\.n8n"
            $clawDir = "$env:USERPROFILE\.openclaw"
            if (Test-Path $n8nDir) { cmd.exe /c "rmDir /S /Q `"$n8nDir`"" }
            if (Test-Path $clawDir) { cmd.exe /c "rmDir /S /Q `"$clawDir`"" }
            $global:installStep++
            Start-NextStep
        }
        elseif ($global:installStep -eq 5) {
            $statusLabel.Text = "Cleanup Perfect. Everything removed."
            $progressBar.Value = 100
            $uninstallButton.Text = "Exit"
            $uninstallButton.Enabled = $true
            $timer.Stop()
            $global:installStep = 999
            Write-Log "`r`n--- Uninstall Complete ---"
            Update-TextBox
        }
    }
    catch {
        $timer.Stop()
        "ERROR: $($_.Exception.Message)" | Out-File -FilePath $logFile -Append
        Update-TextBox
    }
}

$timer.Add_Tick({
        if ($global:installStep -eq 999) { return }
        if ($global:installProcess -ne $null) {
            Update-TextBox
            if ($global:installProcess.HasExited) {
                $global:installProcess = $null
                $global:installStep++
                Start-NextStep
            }
        }
    })

$uninstallButton.Add_Click({
        if ($global:installStep -eq 999) { $form.Close(); return }
        $uninstallButton.Enabled = $false
        Write-Log "Initiating Axiom Nexus Sovereign AI Suite Removal..."
        $global:installStep = 1
        Start-NextStep
        $timer.Start()
    })

$form.ShowDialog() | Out-Null

# SIG # Begin signature block
# MIIFdgYJKoZIhvcNAQcCoIIFZzCCBWMCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUqQeoUd2UAfGKnbVnDrS/Sfye
# VhmgggMOMIIDCjCCAfKgAwIBAgIQE0cy1VHaN7tJftbFBRHhijANBgkqhkiG9w0B
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
# FgQU1RKxuyzBetWnn6LLs7qNzQZiw0owDQYJKoZIhvcNAQEBBQAEggEAWhxRrt+b
# NFxfDJaVApwAq9Z02s+0Q9dZDya1wL62q7vAnDZxG+3b6yyzTtFrLI6QOWlQMljq
# NEJlBfgOqUHvYMH+flFPmFy/CSaW0v7FVAdBHahLA3k6OaEUewjPRW7lhSqz0N3B
# sq273rT2plvGTUj8LfGt3caggph3xGX5Wr8kxZhRvEFPsPI4AUP4pWRUE+r/HSW3
# 1f7HYKG8JuTcgVVt81857Qh/M/+1MsG/6r4nA0F4cZ/sRh2hkom42WTh2HKnsvC5
# W0BzS30Ic8VQGUlSyGF+wkF4NyjBk3KdMYi8+nrP1D1hqQ//rxquHFfWVZ5piafl
# 95DkIaUUXIJoUQ==
# SIG # End signature block
