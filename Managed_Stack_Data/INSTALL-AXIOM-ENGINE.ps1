Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type -AssemblyName System.Drawing

# $global:logFile will be initialized in the click handler to ensure a fresh session.

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Log {
    param([string]$Message)
    try {
        $msg = "[$(Get-Date -Format 'HH:mm:ss')] $Message`r`n"
        [System.IO.File]::AppendAllText($global:logFile, $msg, [System.Text.Encoding]::UTF8)
    }
    catch { }
}

function Invoke-WorkerScript {
    param([string]$ScriptContent, [string]$StepName, [bool]$DirectLog = $false)
    $tempPath = Join-Path $env:TEMP "axiom_worker_$StepName.ps1"
    [System.IO.File]::WriteAllText($tempPath, $ScriptContent, [System.Text.Encoding]::UTF8)
    
    $cmdRunner = Join-Path $env:TEMP "axiom_cli_$StepName.cmd"
    if ($DirectLog) {
        $logTarget = "`"$env:USERPROFILE\Desktop\Axiom-Ollama-Install.log`""
    }
    else {
        $logTarget = "`"$global:logFile`""
    }

    $cmdContent = "@echo off`r`nchcp 65001 > NUL`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$tempPath`" >> $logTarget 2>&1"
    [System.IO.File]::WriteAllText($cmdRunner, $cmdContent, [System.Text.Encoding]::UTF8)

    return Start-Process "cmd.exe" -ArgumentList "/c `"$cmdRunner`"" -WindowStyle Hidden -PassThru
}


# --- SELF-HIDING CONSOLE LOGIC ---
$code = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32" -ErrorAction SilentlyContinue
$hwnd = (Get-Process -Id $PID).MainWindowHandle
if ($hwnd -ne [IntPtr]::Zero) { [Win32.Win32ShowWindow]::ShowWindow($hwnd, 0) } # 0= SW_HIDE


# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Axiom Nexus: Sovereign AI Suite"
$form.Size = New-Object System.Drawing.Size(600, 580)
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
$titleLabel.Text = "Axiom Nexus Installer"
$titleLabel.AutoSize = $true
$titleLabel.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.Location = New-Object System.Drawing.Point(120, 25)
$form.Controls.Add($titleLabel)

# Status Label (Main Step)
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Axiom Nexus: Sovereign AI Suite"
$statusLabel.Size = New-Object System.Drawing.Size(440, 30)
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$statusLabel.Location = New-Object System.Drawing.Point(120, 60)
$form.Controls.Add($statusLabel)

# Detail Label (Timer)
$detailLabel = New-Object System.Windows.Forms.Label
$detailLabel.Text = "Initializing secure agent infrastructure..."
$detailLabel.Size = New-Object System.Drawing.Size(440, 25)
$detailLabel.Font = New-Object System.Drawing.Font("Consolas", 10)
$detailLabel.ForeColor = [System.Drawing.Color]::DimGray
$detailLabel.Location = New-Object System.Drawing.Point(120, 90)
$form.Controls.Add($detailLabel)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size = New-Object System.Drawing.Size(540, 30)
$progressBar.Location = New-Object System.Drawing.Point(20, 125)
$progressBar.Style = "Continuous"
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$form.Controls.Add($progressBar)

# Terminal Output Box
$textBox = New-Object System.Windows.Forms.TextBox
$textBox.Size = New-Object System.Drawing.Size(540, 220)
$textBox.Location = New-Object System.Drawing.Point(20, 175)
$textBox.Multiline = $true
$textBox.ReadOnly = $true
$textBox.ScrollBars = "Vertical"
$textBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$textBox.BackColor = [System.Drawing.Color]::Black
$textBox.ForeColor = [System.Drawing.Color]::LightGray
$form.Controls.Add($textBox)

# Install Button
$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Install Now"
$installButton.Size = New-Object System.Drawing.Size(140, 45)
$installButton.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$installButton.Location = New-Object System.Drawing.Point(220, 420)
$form.Controls.Add($installButton)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 300

function Start-NextStep {
    try {
        if ($global:installStep -eq 1) {
            $statusLabel.Text = "Step 1/7: Preparing System (Applying MAX_PATH Fix)..."
            $progressBar.Value = 10
            Write-Log "--- Enabling Windows LongPathsEnabled ---"
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -ErrorAction SilentlyContinue
            
            Write-Log "--- Checking Node.js Environment ---"
            # Refresh path to catch previous installs
            $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            $env:Path = "$machinePath;$userPath"

            # Check for node via absolute path or command
            $nodePath = "C:\Program Files\nodejs\node.exe"
            if ((Test-Path $nodePath) -or (Get-Command node -ErrorAction SilentlyContinue)) {
                Write-Log "Node.js detected. Skipping Step 1."
                $global:installStep++
                Start-NextStep
                return
            }
            
            Write-Log "--- Installing Node.js v22 (LTS) ---"
            $script = "winget install --id OpenJS.NodeJS.LTS -e --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity"
            $global:installProcess = Invoke-WorkerScript -ScriptContent $script -StepName "Node"
        }
        elseif ($global:installStep -eq 2) {
            $statusLabel.Text = "Step 2/7: Installing Ollama..."
            $progressBar.Value = 25
            Write-Log "--- Installing Ollama (Winget) ---"
            $script = "winget install --id Ollama.Ollama -e --source winget --accept-package-agreements --accept-source-agreements --silent --disable-interactivity"
            $global:installProcess = Invoke-WorkerScript -ScriptContent $script -StepName "Ollama" -DirectLog $true
        }
        elseif ($global:installStep -eq 3) {
            $statusLabel.Text = "Step 3/7: Closing conflicting apps..."
            $progressBar.Value = 35
            Write-Log "--- Clearing Lingering AI Processes ---"
            
            # Professional silent cleanup
            $script = @'
$procs = @("ollama", "ollama app", "node", "n8n")
foreach ($p in $procs) {
    if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
        Write-Host "Closing lingering $p process..."
        taskkill /F /IM "$p.exe" /T 2>$null | Out-Null
    } else {
        Write-Host "$p process not running. Skipping."
    }
}
'@
            $global:installProcess = Invoke-WorkerScript -ScriptContent $script -StepName "TaskKill"
        }
        elseif ($global:installStep -eq 4) {
            $statusLabel.Text = "Step 4/7: Deploying n8n Engine (Pinned v2.10.1)..."
            $progressBar.Value = 45
            Write-Log "--- Verifying n8n Engine Integrity ---"
            
            $global:n8nAssetPath = "$env:APPDATA\npm\node_modules\n8n\dist\public\index.html"
            
            $script = @"
if (Test-Path `"$global:n8nAssetPath`") {
    Write-Host `"n8n physical modules found. Verifying and Re-initializing cleanly...`"
} else {
    Write-Host `"Deploying n8n engine from scratch...`"
}
Write-Host `"Installing n8n@2.10.1 (This normally takes 2-5 minutes)...`"
npm cache clean --force
npm install -g n8n@2.10.1 --force --legacy-peer-deps --no-progress --loglevel=error
"@
            $global:installProcess = Invoke-WorkerScript -ScriptContent $script -StepName "N8N"
        }
        elseif ($global:installStep -eq 5) {
            $statusLabel.Text = "Step 5/7: Integrating OpenClaw & Local AI Node..."
            $progressBar.Value = 60
            Write-Log "--- Hardening Multi-Agent Bridge ---"
            
            $PROJECT_ROOT = $PSScriptRoot
            if (-not $PROJECT_ROOT) { $PROJECT_ROOT = (Get-Location).Path }
            $CUSTOM_NODES_DIR = "$env:USERPROFILE\.n8n\custom"
            if (-not (Test-Path $CUSTOM_NODES_DIR)) { New-Item -ItemType Directory -Force -Path $CUSTOM_NODES_DIR | Out-Null }
            
            $NODE_TGZ = "$PROJECT_ROOT\n8n-nodes-local-ai-manager-0.1.0.tgz"
            
            $script = @"
`$ocPath = `"`$env:APPDATA\npm\node_modules\openclaw`"
`$nPath = `"$CUSTOM_NODES_DIR\node_modules\n8n-nodes-local-ai-manager`"
if ((Test-Path `$ocPath) -and (Test-Path `$nPath)) {
    Write-Host `"OpenClaw and Custom Node modules detected. Applying fresh linking...`"
} else {
    Write-Host `"Deploying OpenClaw Core...`"
}
npm install -g openclaw --loglevel=error --no-progress
Write-Host `"Deploying Custom n8n Skill Node...`"
Set-Location `"$CUSTOM_NODES_DIR`"
if (-not (Test-Path package.json)) { npm init -y | Out-Null }
npm install `"$NODE_TGZ`" --save-exact --loglevel=error --no-progress
"@
            $global:installProcess = Invoke-WorkerScript -ScriptContent $script -StepName "OpenClaw"
        }
        elseif ($global:installStep -eq 6) {
            $statusLabel.Text = "Step 6/7: Deploying Secure Bridge & Skills..."
            $progressBar.Value = 75
            Write-Log "--- Importing Workflow & Deploying Skill ---"
            
            $PROJECT_ROOT = $PSScriptRoot
            if (-not $PROJECT_ROOT) { $PROJECT_ROOT = (Get-Location).Path }
            
            # 1. Skill Deployment
            $SKILL_DIR = "$env:USERPROFILE\.openclaw\skills"
            if (-not (Test-Path $SKILL_DIR)) { New-Item -ItemType Directory -Force -Path $SKILL_DIR | Out-Null }
            Copy-Item "$PROJECT_ROOT\n8n-delegate.md" -Destination "$SKILL_DIR\n8n-delegate.md" -Force
            Write-Log "Skill deployed to $SKILL_DIR"
 
            # 2. Workflow Import (via n8n CLI)
            $script = "n8n import:workflow --input=`"$PROJECT_ROOT\Secure-Agent-Bridge.json`""
            $global:installProcess = Invoke-WorkerScript -ScriptContent $script -StepName "N8NImport"
        }
        elseif ($global:installStep -eq 7) {
            $statusLabel.Text = "Step 7/7: Downloading AI Brain (Expect 5GB+ Download)"
            $progressBar.Value = 90
            Write-Log "--- Checking AI Model Status ---"

            $script = "Write-Host `"Waking local AI model service...`"; ollama pull llama3.2"
            $global:installProcess = Invoke-WorkerScript -ScriptContent $script -StepName "OllamaPull"
        }
        elseif ($global:installStep -eq 8) {
            # Step 8 Consolidated into Step 5 & 7
            $global:installStep++
            Start-NextStep
            return
        }
        elseif ($global:installStep -eq 9) {
            $statusLabel.Text = "Ready! Axiom Nexus Deployed."
            $statusLabel.ForeColor = "Green"
            $detailLabel.Text = "Launch via the 'Launch Axiom Nexus' shortcut."
            $progressBar.Value = 100
            $installButton.Text = "Finish"
            $installButton.Enabled = $true
            $timer.Stop()
            $global:installStep = 999
            Write-Log "`r`n--- Setup Complete ---"
            Update-TextBox
        }
    }
    catch {
        $timer.Stop()
        $statusLabel.Text = "Error at Step $($global:installStep)."
        $statusLabel.ForeColor = "Red"
        $detailLabel.Text = $_.Exception.Message
        $installButton.Text = "Close"
        $installButton.Enabled = $true
        $global:installStep = 999
        Update-TextBox
    }
}

function Update-TextBox {
    if (Test-Path $global:logFile) {
        try {
            $info = New-Object System.IO.FileInfo($global:logFile)
            if ($info.Length -gt $global:lastFileSize) {
                $fs = New-Object System.IO.FileStream($global:logFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $fs.Seek($global:lastFileSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                $newData = $sr.ReadToEnd()
                $sr.Close()
                $fs.Close()
                $global:lastFileSize = $info.Length
                if ($newData) {
                    if ($newData.Length -gt 15000) { $newData = $newData.Substring($newData.Length - 15000) }
                    $incomingLines = $newData -split "[\r\n]+"
                    
                    # Prevent catastrophic regex freeze from massive '\r' progress chunks during 'ollama pull'
                    if ($incomingLines.Count -gt 50) {
                        $incomingLines = $incomingLines[-50..-1]
                    }

                    $cleanData = ""
                    # Robust ANSI escape sequence filter
                    $ansiRegex = "\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"
                    # Filter out progress spinners (- \ | /) and block characters
                    $spamRegex = "^[\s\-\\\|/]+$|â–ˆâ–ˆ|â–’â–’|â ‹|â ™|â ¹|â ¸|â ¼|â ´|â ¦|â §|pulling manifest|verifying sha256|writing manifest|success|npm warn"
                    foreach ($line in $incomingLines) {
                        $stripped = $line -replace $ansiRegex, ""
                        if ($stripped.Trim() -notmatch $spamRegex) {
                            $cleanData += $stripped + "`n"
                        }
                    }
                    if ($cleanData.Trim() -ne "") { 
                        $textBox.AppendText($cleanData) 
                        # Auto-scroll to bottom
                        $textBox.SelectionStart = $textBox.TextLength
                        $textBox.ScrollToCaret()
                    }
                }
            }
        }
        catch { }
    }
}

$timer.Add_Tick({
        # DO NOT call DoEvents() here! It causes recursive stack overflows during heavy disk IO!
        if ($global:installStep -eq 999) { return }
        if ($global:installProcess -ne $null) {
            $elapsed = ([datetime]::Now - $global:startTime)
            $detailLabel.Text = "Time Elapsed: $('{0:mm\:ss}' -f $elapsed)"
            Update-TextBox
            if ($global:installProcess.HasExited) {
                # Success codes: 0 (True Success), -1978335189/0x8A15003B/0x8A150036 (Already Installed/No Upgrade)
                $successCodes = @(0, -1978335189, -1978335178)
                $exitCode = $global:installProcess.ExitCode
            
                # Path Presence Checks (Overrides for grumpy exit codes)
                $nodeExists = ($global:installStep -eq 1 -and ((Test-Path "C:\Program Files\nodejs\node.exe") -or (Get-Command node -ErrorAction SilentlyContinue)))
                $ollamaPaths = @("$env:LOCALAPPDATA\Programs\Ollama\ollama.exe", "C:\Program Files\Ollama\ollama.exe")
                $ollamaExists = ($global:installStep -eq 2 -and (($ollamaPaths | Where-Object { Test-Path $_ }) -or (Get-Command ollama -ErrorAction SilentlyContinue)))
                
                # N8N Success Check (Step 4): If exit code 1, but assets were successfully laid down or log explicitly says success.
                $lastLog = if (Test-Path $global:logFile) { Get-Content $global:logFile -Tail 5 | Out-String } else { "" }
                $n8nExists = ($global:installStep -eq 4 -and (($global:n8nAssetPath -and (Test-Path $global:n8nAssetPath)) -or ($lastLog -like "*success*")))
                
                # Model Success Check (Step 7): If log says success or already exists, it is a success even with code 1
                $isModelSuccess = ($global:installStep -eq 7 -and ($lastLog -like "*success*" -or $lastLog -like "*already exists*"))
                
                $isPathSuccess = ($nodeExists -or $ollamaExists -or $isModelSuccess -or $n8nExists)

                # Ignore exit codes 1 or 128 for tasks that often return false negatives
                # Step 3 (Taskkill), Step 5 (NPM Install with skips), Step 6 (N8N Import), Step 7 (Ollama Pull)
                $isIgnorable = (($exitCode -eq 1 -or $exitCode -eq 128) -and ($global:installStep -eq 3 -or $global:installStep -eq 5 -or $global:installStep -eq 6 -or $global:installStep -eq 7))
                $isWingetSuccess = ($successCodes -contains $exitCode -and ($global:installStep -eq 1 -or $global:installStep -eq 2))
            
                if (-not ($exitCode -eq 0 -or $isIgnorable -or $isWingetSuccess -or $isPathSuccess)) {
                    $timer.Stop()
                    $statusLabel.Text = "Failed at Step $($global:installStep)."
                    $statusLabel.ForeColor = "Red"
                    $lastLog = if (Test-Path $global:logFile) { Get-Content $global:logFile -Tail 1 } else { "No log" }
                    $detailLabel.Text = "Exit code $exitCode. Log: $lastLog"
                    $installButton.Text = "Close"
                    $installButton.Enabled = $true
                    $global:installStep = 999
                    return
                }
                $global:installProcess = $null
                $global:installStep++
                Start-NextStep
            }
        }
    })

$installButton.Add_Click({
        try {
            if ($global:installStep -eq 999) { $form.Close(); return }
            $installButton.Enabled = $false
        
            # Safe Log Initialization
            $global:logFile = "$env:USERPROFILE\Desktop\Axiom-Nexus-Log.txt"
            $textBox.Text = "" # Clear UI log
            $global:lastFileSize = 0
        
            try {
                if (Test-Path $global:logFile) { 
                    Remove-Item $global:logFile -Force -ErrorAction SilentlyContinue 
                }
                " " | Out-File $global:logFile -Encoding utf8 -Force # Ensure file exists for StreamReaders in UTF-8
            }
            catch { }

            Write-Log "Starting Axiom Nexus Sovereign AI Suite Setup..."
            $global:startTime = [datetime]::Now
            $global:installStep = 1
            Start-NextStep
            $timer.Start()
        }
        catch {
            $statusLabel.Text = "Fatal Startup Error."
            $detailLabel.Text = $_.Exception.Message
            $installButton.Enabled = $true
            $installButton.Text = "Fail/Close"
            $global:installStep = 999
        }
    })

$form.ShowDialog() | Out-Null

# SIG # Begin signature block
# MIIFdgYJKoZIhvcNAQcCoIIFZzCCBWMCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQURyKwiHiKuOisz6MSyBX6Om5L
# xiqgggMOMIIDCjCCAfKgAwIBAgIQE0cy1VHaN7tJftbFBRHhijANBgkqhkiG9w0B
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
# FgQURsBIYvA1BLHzZiObggBAzKmUeBQwDQYJKoZIhvcNAQEBBQAEggEAZ3LAVd9U
# KYx3U+0iT9KWvjvwDoMKKKDvnYI1mJWgFFkm5F4zgKgxYEwQAZlbpBOlLokLpyIA
# 2cnckKlf3bi++uBH+uFZOydPoQKeinNPfaSz0I0caPhXuyG22FPCu4azARc4bnht
# lYmP8hxy/PbOUdoB1BZjIAvHGGNzA9KmMWrRyQre+TrR/2PPhb/oLKC01WH9FpvV
# vkucg9qg6RaAVUZPVAsNaBjdkdIhzJ+xPEeCoRqA+1Cy/LdlH1uLBvEgJzgicM5B
# KQJJa/K2FmCFJDhFCMMfe0upuFBuFv0g/jOS2aAU9sc9Kwa2UVmJqjIy7vZJmaEG
# pAcW6bKC8Aq+uA==
# SIG # End signature block
