Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type -AssemblyName System.Drawing

# Keep npm/node stderr notices from being surfaced as terminating PowerShell errors.
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $global:PSNativeCommandUseErrorActionPreference = $false
}

# Launcher must run elevated to reliably stop stale node/n8n processes.
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    [System.Windows.Forms.MessageBox]::Show(
        "Axiom Launch Center must run as Administrator for reliable restart/port cleanup. Please re-open using 'Run as administrator'.",
        "Axiom Nexus",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit
}

# --- SINGLE INSTANCE GUARD ---
$mutexCreated = $false
$script:appMutex = New-Object System.Threading.Mutex($true, "Global\AxiomLaunchCenterMutex", [ref]$mutexCreated)
if (-not $mutexCreated) {
    [System.Windows.Forms.MessageBox]::Show(
        "Axiom Launch Center is already running.",
        "Axiom Nexus",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit
}

# --- DEBUG/LAUNCH FLAGS ---
$debugMode = $true
$autoCloseLauncher = $false
$script:hubLaunched = $false
$script:startInProgress = $false
$script:startDeadline = $null
$script:hubProcessId = $null
$script:n8nProcessId = $null
$script:mcpBridgeProcessId = $null
$script:hubProfileDir = Join-Path $env:TEMP "AxiomHubProfile"
$script:routerWorkflowId = "dTzRbVa8bRBZTZ6O"

# --- CONSOLE VISIBILITY ---
$code = '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);'
Add-Type -MemberDefinition $code -Name "Win32ShowWindow" -Namespace "Win32" -ErrorAction SilentlyContinue
$hwnd = (Get-Process -Id $PID).MainWindowHandle
if (-not $debugMode -and $hwnd -ne [IntPtr]::Zero) { [Win32.Win32ShowWindow]::ShowWindow($hwnd, 0) }

# --- INITIALIZATION ---
$script:logFile = $null
$script:lastFileSize = 0

function New-BootLogFile {
    $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
    $script:logFile = Join-Path $env:TEMP ("axiom_boot_{0}.log" -f $stamp)
    try {
        New-Item -Path $script:logFile -ItemType File -Force -ErrorAction Stop | Out-Null
    }
    catch {
        # Fallback to a per-process filename if timestamp creation races.
        $script:logFile = Join-Path $env:TEMP ("axiom_boot_{0}.log" -f $PID)
        New-Item -Path $script:logFile -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
    }
    $script:lastFileSize = 0
}

New-BootLogFile

function Test-OllamaReady {
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:11434/api/tags" -TimeoutSec 2 -ErrorAction Stop
        return $resp.StatusCode -eq 200
    }
    catch {
        return $false
    }
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

function Test-McpBridgeReady {
    try {
        $resp = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:3055/health" -TimeoutSec 2 -ErrorAction Stop
        return $resp.StatusCode -eq 200
    }
    catch {
        return $false
    }
}

function Ensure-McpBridgeRunning {
    param(
        [System.Windows.Forms.TextBox]$OutputBox
    )

    if (Test-McpBridgeReady) {
        $OutputBox.AppendText("Model bridge already running on 127.0.0.1:3055`r`n")
        return $true
    }

    $bridgeRoot = Join-Path (Split-Path $PSScriptRoot -Parent) "Axiom-MCP-Server"
    if (-not (Test-Path $bridgeRoot)) {
        $OutputBox.AppendText("WARNING: Axiom-MCP-Server directory not found. Model install bridge disabled.`r`n")
        return $false
    }

    $bridgeEntry = Join-Path $bridgeRoot "dist\\index.js"
    $bridgeSource = Join-Path $bridgeRoot "index.ts"
    $bridgeNodeModules = Join-Path $bridgeRoot "node_modules"
    if (-not (Test-Path $bridgeNodeModules)) {
        $OutputBox.AppendText("Installing model bridge dependencies...`r`n")
        Push-Location $bridgeRoot
        try {
            $installOut = & npm install --no-progress 2>&1 | Out-String
            if ($installOut) { $OutputBox.AppendText($installOut.Trim() + "`r`n") }
            if ($LASTEXITCODE -ne 0) {
                $OutputBox.AppendText("ERROR: Failed to install model bridge dependencies (exit $LASTEXITCODE).`r`n")
                return $false
            }
        }
        catch {
            $OutputBox.AppendText("ERROR: Failed to install model bridge dependencies: $($_.Exception.Message)`r`n")
            return $false
        }
        finally {
            Pop-Location
        }
    }

    $needsBuild = -not (Test-Path $bridgeEntry)
    if (-not $needsBuild -and (Test-Path $bridgeSource)) {
        try {
            $srcTime = (Get-Item $bridgeSource).LastWriteTimeUtc
            $distTime = (Get-Item $bridgeEntry).LastWriteTimeUtc
            if ($srcTime -gt $distTime) { $needsBuild = $true }
        }
        catch { }
    }

    if ($needsBuild) {
        $OutputBox.AppendText("Building model bridge service...`r`n")
        Push-Location $bridgeRoot
        try {
            $buildOut = & npm run build 2>&1 | Out-String
            if ($buildOut) { $OutputBox.AppendText($buildOut.Trim() + "`r`n") }
            if ($LASTEXITCODE -ne 0) {
                $OutputBox.AppendText("ERROR: Failed to build model bridge (exit $LASTEXITCODE).`r`n")
                return $false
            }
        }
        catch {
            $OutputBox.AppendText("ERROR: Failed to build model bridge: $($_.Exception.Message)`r`n")
            return $false
        }
        finally {
            Pop-Location
        }
    }

    if (-not (Test-Path $bridgeEntry)) {
        $OutputBox.AppendText("ERROR: Model bridge entrypoint missing: $bridgeEntry`r`n")
        return $false
    }

    $bridgeLog = Join-Path $env:TEMP "axiom_mcp_bridge.log"
    try {
        $cmd = "/c cd /d `"$bridgeRoot`" && node dist/index.js >> `"$bridgeLog`" 2>&1"
        $bridgeProc = Start-Process cmd.exe -ArgumentList $cmd -WindowStyle Hidden -PassThru -ErrorAction Stop
        if ($bridgeProc) {
            $script:mcpBridgeProcessId = $bridgeProc.Id
            $OutputBox.AppendText("Started model bridge process PID $($script:mcpBridgeProcessId).`r`n")
        }
    }
    catch {
        $OutputBox.AppendText("ERROR: Failed to start model bridge: $($_.Exception.Message)`r`n")
        return $false
    }

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-McpBridgeReady) {
            $OutputBox.AppendText("Model bridge is online.`r`n")
            return $true
        }
    }

    $OutputBox.AppendText("ERROR: Model bridge failed health check on 127.0.0.1:3055.`r`n")
    return $false
}

function Stop-ProcessTreeById {
    param(
        [int]$ProcessId,
        [System.Windows.Forms.TextBox]$OutputBox,
        [string]$Label = "process"
    )

    if ($ProcessId -le 0) { return }
    if (-not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) { return }

    $OutputBox.AppendText("Closing $Label (PID $ProcessId)...`r`n")
    $taskkillOutput = & taskkill /F /PID $ProcessId /T 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        $OutputBox.AppendText("WARNING: Could not stop $Label PID $ProcessId (exit $LASTEXITCODE).`r`n")
        if ($taskkillOutput) {
            $OutputBox.AppendText($taskkillOutput.Trim() + "`r`n")
        }
    }
}

function Stop-ListenersOnPorts {
    param(
        [int[]]$Ports,
        [System.Windows.Forms.TextBox]$OutputBox
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
        Stop-ProcessTreeById -ProcessId $pid -OutputBox $OutputBox -Label "port listener"
    }
}

function Wait-PortsReleased {
    param(
        [int[]]$Ports,
        [System.Windows.Forms.TextBox]$OutputBox,
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

    $OutputBox.AppendText("WARNING: Ports still busy after stop timeout: $($Ports -join ', ').`r`n")
    return $false
}

function Ensure-OllamaRunning {
    param(
        [System.Windows.Forms.TextBox]$OutputBox
    )

    if (Test-OllamaReady) {
        $OutputBox.AppendText("Ollama already running on 127.0.0.1:11434`r`n")
        return $true
    }

    $OutputBox.AppendText("Ollama not detected. Starting Ollama...`r`n")

    $ollamaExe = $null
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($cmd) { $ollamaExe = $cmd.Source }
    if (-not $ollamaExe) {
        $fallback = "C:\Users\Martin\AppData\Local\Programs\Ollama\ollama.exe"
        if (Test-Path $fallback) { $ollamaExe = $fallback }
    }
    if (-not $ollamaExe) {
        $OutputBox.AppendText("ERROR: ollama.exe not found. Install Ollama or add it to PATH.`r`n")
        return $false
    }

    # Headless mode: run server only (no tray/app window).
    try {
        Start-Process -FilePath $ollamaExe -ArgumentList "serve" -WindowStyle Hidden -ErrorAction Stop | Out-Null
    }
    catch {
        $OutputBox.AppendText("ERROR: Failed to launch Ollama server: $($_.Exception.Message)`r`n")
        return $false
    }

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-OllamaReady) {
            $OutputBox.AppendText("Ollama is online.`r`n")
            return $true
        }
    }

    $OutputBox.AppendText("ERROR: Ollama failed health check on 127.0.0.1:11434.`r`n")
    return $false
}

function Stop-AxiomStack {
    param(
        [System.Windows.Forms.TextBox]$OutputBox,
        [switch]$StopOllama
    )

    if ($script:n8nProcessId) {
        Stop-ProcessTreeById -ProcessId $script:n8nProcessId -OutputBox $OutputBox -Label "n8n runtime"
        $script:n8nProcessId = $null
    }

    if ($script:mcpBridgeProcessId) {
        Stop-ProcessTreeById -ProcessId $script:mcpBridgeProcessId -OutputBox $OutputBox -Label "model bridge"
        $script:mcpBridgeProcessId = $null
    }

    Stop-ListenersOnPorts -Ports @(5678, 5679, 3055) -OutputBox $OutputBox

    $targets = @("node", "n8n")
    if ($StopOllama) { $targets += @("ollama", "ollama app") }

    foreach ($p in $targets) {
        if (Get-Process -Name $p -ErrorAction SilentlyContinue) {
            $OutputBox.AppendText("Closing $p...`r`n")
            $taskkillOutput = & taskkill /F /IM "$p.exe" /T 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) {
                $OutputBox.AppendText("WARNING: Could not stop $p (exit $LASTEXITCODE).`r`n")
                if ($taskkillOutput) {
                    $OutputBox.AppendText($taskkillOutput.Trim() + "`r`n")
                }
            }
        }
    }

    $portsReleased = Wait-PortsReleased -Ports @(5678, 5679, 3055) -OutputBox $OutputBox
    if (-not $portsReleased) {
        $OutputBox.AppendText("Retrying forced listener cleanup on 5678/5679/3055...`r`n")
        Stop-ListenersOnPorts -Ports @(5678, 5679, 3055) -OutputBox $OutputBox
        $portsReleased = Wait-PortsReleased -Ports @(5678, 5679, 3055) -OutputBox $OutputBox -TimeoutSeconds 8
    }

    if (-not $portsReleased) {
        $OutputBox.AppendText("ERROR: Could not free engine ports (5678/5679/3055). Resolve stale process lock before restart.`r`n")
        return $false
    }

    return $true
}

function Sync-CustomNodePackage {
    param(
        [System.Windows.Forms.TextBox]$OutputBox
    )

    $tarball = $null
    $sourcePkgDir = Join-Path (Split-Path $PSScriptRoot -Parent) "n8n-nodes-local-ai-manager"
    $sourceBuildAttempted = $false
    $sourceBuildFailed = $false

    if (Test-Path (Join-Path $sourcePkgDir "package.json")) {
        $sourceBuildAttempted = $true
        $OutputBox.AppendText("Building local custom node package from source...`r`n")
        Push-Location $sourcePkgDir
        try {
            $buildOut = & npm run build 2>&1 | Out-String
            if ($buildOut) { $OutputBox.AppendText($buildOut.Trim() + "`r`n") }
            if ($LASTEXITCODE -ne 0) {
                $OutputBox.AppendText("ERROR: npm run build failed (exit $LASTEXITCODE).`r`n")
                $sourceBuildFailed = $true
            } else {
                $packOut = & npm pack 2>&1 | Out-String
                if ($packOut) { $OutputBox.AppendText($packOut.Trim() + "`r`n") }
                if ($LASTEXITCODE -eq 0) {
                    $builtTarball = Get-ChildItem -Path $sourcePkgDir -Filter "n8n-nodes-local-ai-manager-*.tgz" -File -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending |
                        Select-Object -First 1
                    if ($builtTarball) {
                        $copiedTarball = Join-Path $PSScriptRoot $builtTarball.Name
                        Copy-Item -Path $builtTarball.FullName -Destination $copiedTarball -Force
                        $tarball = $copiedTarball
                        $OutputBox.AppendText("Updated package tarball: $($builtTarball.Name)`r`n")
                    }
                } else {
                    $OutputBox.AppendText("ERROR: npm pack failed (exit $LASTEXITCODE).`r`n")
                    $sourceBuildFailed = $true
                }
            }
        }
        catch {
            $OutputBox.AppendText("ERROR: Source package build failed: $($_.Exception.Message)`r`n")
            $sourceBuildFailed = $true
        }
        finally {
            Pop-Location
        }
    }

    if ($sourceBuildAttempted -and $sourceBuildFailed) {
        $OutputBox.AppendText("ERROR: Aborting startup to avoid loading stale custom node package.`r`n")
        return $false
    }

    if (-not $tarball) {
        $tarballs = Get-ChildItem -Path $PSScriptRoot -Filter "n8n-nodes-local-ai-manager-*.tgz" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        if ($tarballs -and $tarballs.Count -gt 0) {
            $tarball = $tarballs[0].FullName
        }
    }

    if (-not $tarball) {
        $OutputBox.AppendText("WARNING: No custom node package tarball found in Managed_Stack_Data.`r`n")
        return $false
    }

    $nodesDir = Join-Path $env:USERPROFILE ".n8n\nodes"

    try {
        New-Item -Path $nodesDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }
    catch {
        $OutputBox.AppendText("ERROR: Could not create n8n nodes directory: $($_.Exception.Message)`r`n")
        return $false
    }

    $pkgJsonPath = Join-Path $nodesDir "package.json"
    if (-not (Test-Path $pkgJsonPath)) {
        $bootstrap = @{
            name = "installed-nodes"
            private = $true
            dependencies = @{}
        } | ConvertTo-Json -Depth 6
        Set-Content -Path $pkgJsonPath -Value $bootstrap -Encoding UTF8
    }

    $OutputBox.AppendText("Syncing custom node package: $([System.IO.Path]::GetFileName($tarball))`r`n")
    Push-Location $nodesDir
    try {
        $installOut = & npm install --force "file:$tarball" 2>&1 | Out-String
        if ($installOut) { $OutputBox.AppendText($installOut.Trim() + "`r`n") }
        if ($LASTEXITCODE -ne 0) {
            $OutputBox.AppendText("ERROR: npm install failed with exit code $LASTEXITCODE.`r`n")
            return $false
        }
    }
    catch {
        $OutputBox.AppendText("ERROR: Failed to sync custom node package: $($_.Exception.Message)`r`n")
        return $false
    }
    finally {
        Pop-Location
    }

    $parserPath = Join-Path $nodesDir "node_modules\n8n-nodes-local-ai-manager\dist\lib\axiomParser.js"
    if (-not (Test-Path $parserPath)) {
        $OutputBox.AppendText("ERROR: Custom parser node was not installed correctly (axiomParser.js missing).`r`n")
        return $false
    }

    try {
        $pkgPath = Join-Path $nodesDir "node_modules\n8n-nodes-local-ai-manager\package.json"
        $pkgVersion = if (Test-Path $pkgPath) { (Get-Content $pkgPath -Raw | ConvertFrom-Json).version } else { "unknown" }
        $parserHash = (Get-FileHash -Path $parserPath -Algorithm SHA256).Hash.Substring(0, 12)
        $OutputBox.AppendText("Installed custom node version: $pkgVersion (parser sha256:$parserHash)`r`n")
    }
    catch {
        $OutputBox.AppendText("Warning: Could not compute parser fingerprint: $($_.Exception.Message)`r`n")
    }

    $OutputBox.AppendText("Custom node package synced successfully.`r`n")
    return $true
}

function Close-HubWindow {
    param(
        [System.Windows.Forms.TextBox]$OutputBox
    )

    if ($script:hubProcessId) {
        try {
            if (Get-Process -Id $script:hubProcessId -ErrorAction SilentlyContinue) {
                Stop-Process -Id $script:hubProcessId -Force -ErrorAction SilentlyContinue
                $OutputBox.AppendText("Closed existing Hub window.`r`n")
            }
        }
        catch { }
        $script:hubProcessId = $null
    }

    # Also close stale Edge app windows launched for Axiom Hub profile.
    try {
        $staleHub = Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" -ErrorAction SilentlyContinue |
            Where-Object {
                $_.CommandLine -like "*Axiom-Hub.html*" -or
                $_.CommandLine -like "*AxiomHubProfile*"
            }

        foreach ($proc in $staleHub) {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
    catch { }
}

function Start-AxiomStack {
    param(
        [System.Windows.Forms.TextBox]$OutputBox,
        [System.Windows.Forms.Label]$StatusLabel,
        [System.Windows.Forms.Timer]$UiTimer
    )

    if ($script:startInProgress) {
        $OutputBox.AppendText("Startup already in progress. Please wait...`r`n")
        return
    }
    $script:startInProgress = $true
    $script:hubLaunched = $false
    $script:startDeadline = (Get-Date).AddMinutes(2)

    $UiTimer.Stop()
    New-BootLogFile

    $OutputBox.AppendText("--- Clearing Lingering AI Processes ---`r`n")
    if (-not (Stop-AxiomStack -OutputBox $OutputBox)) {
        $StatusLabel.Text = "Could not clear existing n8n ports."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        $script:startInProgress = $false
        return
    }

    $OutputBox.AppendText("--- Verifying Ollama ---`r`n")
    if (-not (Ensure-OllamaRunning -OutputBox $OutputBox)) {
        $StatusLabel.Text = "Ollama startup failed."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        $script:startInProgress = $false
        return
    }

    $OutputBox.AppendText("--- Starting Model Bridge ---`r`n")
    if (-not (Ensure-McpBridgeRunning -OutputBox $OutputBox)) {
        $StatusLabel.Text = "Model bridge startup failed."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        $script:startInProgress = $false
        return
    }

    $OutputBox.AppendText("--- Booting Autonomous Engine ---`r`n")
    $sandboxDirs = @("C:\Axiom_Files", "$env:USERPROFILE\.n8n-files\Axiom_Files")
    foreach ($sandboxDir in $sandboxDirs) {
        if (Test-Path $sandboxDir) { continue }
        try {
            New-Item -Path $sandboxDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
            $OutputBox.AppendText("Created sandbox directory: $sandboxDir`r`n")
        }
        catch {
            $OutputBox.AppendText("Warning: Could not create sandbox directory $sandboxDir. $($_.Exception.Message)`r`n")
        }
    }

    $OutputBox.AppendText("--- Syncing Local Custom Nodes ---`r`n")
    if (-not (Sync-CustomNodePackage -OutputBox $OutputBox)) {
        $StatusLabel.Text = "Custom node sync failed."
        $StatusLabel.ForeColor = [System.Drawing.Color]::Red
        $script:startInProgress = $false
        return
    }

    $routerPath = Join-Path $PSScriptRoot "Axiom-Master-Router.json"
    if (Test-Path $routerPath) {
        $OutputBox.AppendText("--- Importing Router Workflow ---`r`n")
        try {
            $importOutput = & n8n import:workflow --input="$routerPath" 2>&1 | Out-String
            if ($importOutput) {
                $OutputBox.AppendText($importOutput.Trim() + "`r`n")
            }
        }
        catch {
            $OutputBox.AppendText("Warning: Could not import router workflow automatically: $($_.Exception.Message)`r`n")
        }
    }

    $OutputBox.AppendText("--- Publishing Router Workflow ---`r`n")
    try {
        $publishOutput = & n8n publish:workflow --id=$script:routerWorkflowId 2>&1 | Out-String
        if ($publishOutput) {
            $OutputBox.AppendText($publishOutput.Trim() + "`r`n")
        }
    }
    catch {
        $OutputBox.AppendText("Warning: Could not publish workflow automatically: $($_.Exception.Message)`r`n")
    }

    $env:N8N_BLOCK_PYTHON_SANDBOX_TASKS = "true"
    $env:N8N_SKIP_WEBHOOK_DEREGISTRATION_ON_SHUTDOWN = "true"
    $env:WEBHOOK_URL = "http://localhost:5678/"
    $env:N8N_CORS_ALLOWED_ORIGINS = "*"
    $env:N8N_CORS_ALLOWED_HEADERS = "*"
    $env:N8N_DIAGNOSTICS_ENABLED = "false"
    $env:N8N_VERSION_NOTIFICATIONS_ENABLED = "false"
    $restrictFileAccessRoots = @(
        "C:\Axiom_Files",
        "$env:USERPROFILE\.n8n-files",
        "$env:USERPROFILE"
    ) | Where-Object { $_ -and $_.Trim() -ne '' }
    $env:N8N_RESTRICT_FILE_ACCESS_TO = ($restrictFileAccessRoots -join ";")
    $OutputBox.AppendText("N8N_RESTRICT_FILE_ACCESS_TO = $($env:N8N_RESTRICT_FILE_ACCESS_TO)`r`n")
    $env:NODE_FUNCTION_ALLOW_BUILTIN = "fs,path"

    $n8nProc = Start-Process cmd.exe -ArgumentList "/c chcp 65001 > NUL && n8n start > `"$script:logFile`" 2>&1" -WindowStyle Hidden -PassThru
    if ($n8nProc) {
        $script:n8nProcessId = $n8nProc.Id
        $OutputBox.AppendText("Started n8n host process PID $($script:n8nProcessId).`r`n")
    }
    $StatusLabel.Text = "Starting n8n..."
    $StatusLabel.ForeColor = [System.Drawing.Color]::Orange
    $UiTimer.Start()
}

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Axiom Launch Center"
$form.Size = New-Object System.Drawing.Size(600, 520)
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

# Debug controls
$keepOpenCheck = New-Object System.Windows.Forms.CheckBox
$keepOpenCheck.Text = "Keep launcher open (debug)"
$keepOpenCheck.Checked = $true
$keepOpenCheck.AutoSize = $true
$keepOpenCheck.Location = New-Object System.Drawing.Point(20, 370)
$form.Controls.Add($keepOpenCheck)

$restartBtn = New-Object System.Windows.Forms.Button
$restartBtn.Text = "Restart Engine"
$restartBtn.Size = New-Object System.Drawing.Size(130, 30)
$restartBtn.Location = New-Object System.Drawing.Point(20, 400)
$form.Controls.Add($restartBtn)

$stopBtn = New-Object System.Windows.Forms.Button
$stopBtn.Text = "Stop Engine"
$stopBtn.Size = New-Object System.Drawing.Size(130, 30)
$stopBtn.Location = New-Object System.Drawing.Point(160, 400)
$form.Controls.Add($stopBtn)

$openN8nBtn = New-Object System.Windows.Forms.Button
$openN8nBtn.Text = "Open n8n"
$openN8nBtn.Size = New-Object System.Drawing.Size(130, 30)
$openN8nBtn.Location = New-Object System.Drawing.Point(300, 400)
$form.Controls.Add($openN8nBtn)

$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text = "Close Launcher"
$closeBtn.Size = New-Object System.Drawing.Size(130, 30)
$closeBtn.Location = New-Object System.Drawing.Point(430, 400)
$form.Controls.Add($closeBtn)

# Verification Timer
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500

$timer.Add_Tick({
        if ($script:startInProgress -and $script:startDeadline -and (Get-Date) -gt $script:startDeadline) {
            $statusLabel.Text = "Startup timeout. Use Restart Engine."
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            $textBox.AppendText("ERROR: n8n did not become healthy within 2 minutes.`r`n")
            $script:startInProgress = $false
            $timer.Stop()
            return
        }

        if (-not $script:hubLaunched -and (Test-N8nReady)) {
            $script:hubLaunched = $true
            $script:startInProgress = $false
            $timer.Stop()
            $statusLabel.Text = "Axiom Engine Ready. Launching Hub..."
            $statusLabel.ForeColor = [System.Drawing.Color]::Green
            Close-HubWindow -OutputBox $textBox
            try {
                $hubPath = (Get-Item (Join-Path $PSScriptRoot "Axiom-Hub.html")).FullName
                $hubUrl = "file:///" + $hubPath.Replace("\", "/")
                $hubProc = Start-Process "msedge.exe" -ArgumentList "--user-data-dir=`"$script:hubProfileDir`"", "--app=`"$hubUrl`"", "--new-window" -PassThru -ErrorAction Stop
                if ($hubProc) { $script:hubProcessId = $hubProc.Id }
            }
            catch {
                $hubPath = Join-Path $PSScriptRoot "Axiom-Hub.html"
                $hubProc = Start-Process $hubPath -PassThru -ErrorAction SilentlyContinue
                if ($hubProc) { $script:hubProcessId = $hubProc.Id }
            }

            Start-Sleep -Seconds 1
            if ($autoCloseLauncher -and -not $keepOpenCheck.Checked -and -not $debugMode) {
                $form.Close()
            }
            else {
                $statusLabel.Text = "Axiom Engine Ready (debug mode)."
            }
            return
        }

        if ($script:logFile -and (Test-Path $script:logFile)) {
            try {
                $info = New-Object System.IO.FileInfo($script:logFile)
                if ($info.Length -gt $script:lastFileSize) {
                    $fs = New-Object System.IO.FileStream($script:logFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $fs.Seek($script:lastFileSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                    $newData = $sr.ReadToEnd()
                    $sr.Close(); $fs.Close()
                    $script:lastFileSize = $info.Length
                
                    if ($newData) {
                        $textBox.AppendText($newData)
                        $textBox.SelectionStart = $textBox.TextLength
                        $textBox.ScrollToCaret()
                    
                    }
                }
            }
            catch { }
        }
    })

$restartBtn.Add_Click({
        Close-HubWindow -OutputBox $textBox
        $script:hubLaunched = $false
        $script:startInProgress = $false
        Start-AxiomStack -OutputBox $textBox -StatusLabel $statusLabel -UiTimer $timer
    })

$stopBtn.Add_Click({
        $timer.Stop()
        $script:startInProgress = $false
        Close-HubWindow -OutputBox $textBox
        Stop-AxiomStack -OutputBox $textBox -StopOllama
        $statusLabel.Text = "Engine stopped."
        $statusLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    })

$openN8nBtn.Add_Click({
        Start-Process "http://localhost:5678"
    })

$closeBtn.Add_Click({
        $form.Close()
    })

$form.Add_Shown({
        $script:hubLaunched = $false
        Start-AxiomStack -OutputBox $textBox -StatusLabel $statusLabel -UiTimer $timer
    })

$form.Add_FormClosed({
        if ($script:appMutex) {
            try { $script:appMutex.ReleaseMutex() | Out-Null } catch { }
            $script:appMutex.Dispose()
        }
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
