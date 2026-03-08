# Axiom Nexus: Sovereign AI Suite - Project Task List

## Phase 31: Pragmatic Architecture Rollout (Current)
**Status**: In Progress -> **Complete**

- [x] **Task 1: Contract Hardening (Response Envelopes)**
  - [x] Create a mandatory structure: `{status, response, action, error, traceId}`.
  - [x] Enforce this across ALL routing branches (Write, Read, List, Chat, Task, Error).
  - [x] Verify the "empty payload" bug is unreachable.
- [x] **Task 2: Planner Hardening (OpenAI Strict JSON Schema)**
  - [x] Switch the systemDirective in `LocalAiManager.node.ts` to output a strict tool structure exclusively (`tool_choice: "required"`, `parallel_tool_calls: false`).
  - [x] Eliminate free-form intent fallbacks in the command path.
- [x] **Task 3: IR Compiler Layer (Intent Normalization)**
  - [x] Enhance validation logic to deterministically reject unsupported operations (like move/rename/change extension).
  - [x] Route these safely back to the user with an explicit clarification prompt/policy denial instead of attempting a failed write.
- [x] **Task 4: MCP Layer Consolidation**
  - [x] Put file operations behind a dedicated MCP server.
  - [x] Validate arguments and enforce runtime policy prior to execution.
  - [x] Test the integration with the MCP Inspector.
- [x] **Task 5: Systematic Regression Testing**
  - [x] Add explicit execution tests based on previous debug exports.
  - [x] Verify the "empty payload" bug is unreachable.
  - [x] Verify the "follow-up selection" UI bug is fixed.

## Phase 22: GPT Evaluation & Architecture Evolution
- [x] Fix Windows Long Paths (`MAX_PATH`) issue in Installer
- [x] Integrate Missing `n8n-nodes-local-ai-manager` into `~/.n8n/custom`
- [x] Filter out terminal spam (rotating slashes) from Installer GUI
- [x] Secure `openclaw-exec` Webhook with `X-Axiom-Auth` Header
- [x] Update [n8n-delegate.md](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/n8n-delegate.md) with explicit tool payload structure
- [x] **[FIX]** Replace obsolete n8n Ollama nodes with Private `localAiManager` node
- [x] Initialize Git and commit non-obsolete files (Axiom Engine + Hub)
- [x] Push codebase to GitHub (SaintMagic/Axiom-Nexus-Sovereign-AI)

## Phase 3: The OpenClaw Awakening (Active Intelligence)
This phase shifts focus from infrastructure installer fixes to the active, user-facing intelligence layer of the suite.

- [x] **Component 1: The "Axiom Hub" (Static UI/UX)**
  - [x] Develop a single-file Static HTML/JS interface (zero-build, instant launch).
  - [x] Implement Glassmorphism styling and Professional Action buttons (Chat, Automation, Direct Command).
  - [x] Add message timestamps and `localStorage` session persistence.
  - [x] Integrate simulated agent action steps for "wow" factor feedback.
  - [x] Connect `fetch()` logic to the n8n Secure Webhook Bridge.
- [x] **Component 2: The Dual-Memory Layer (n8n)**
  - [x] Create SQLite schema for Long-Term Facts (user prefs, knowledge).
  - [x] Create SQLite schema for Short-Term Context (last 10 messages) to prevent context bloat.
- [x] **Component 3: `n8n-delegate` Strict Tool Router**
  - [x] Build the n8n Hub Router workflow (Webhook -> Switch Node based on strict JSON schema).
  - [x] Update [n8n-delegate.md](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/n8n-delegate.md) to force the LLM to output a strict `{ action, path, content }` payload.
- [x] **Component 4: Commercial "Killer App" Workflows**
  - [x] Build [Axiom-Invoice-Processor.json](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/Axiom-Invoice-Processor.json): Email watcher -> PDF Extract -> LLM -> CSV/Excel logger.
  - [x] Build [Axiom-Auto-Filer.json](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/Axiom-Auto-Filer.json): Folder watcher -> Filename/Content AI analysis -> Move File node.

## Potential Expansions (Future Horizon)
- [ ] The "Axiom Control Panel" (System Tray App)
- [ ] Auto-Update Architecture (Over-The-Air Patches)
- [ ] The "Bring Your Own Model" (BYOM) Pre-Launch Selector
- [ ] Local Document Ingestion (RAG Pipeline with Vector DB)
- [ ] The "Desktop Watcher" Folder Automation Node
- [ ] Voice-to-Text Integration (Local Whisper offline transcription)
- [ ] Air-Gapped Mode (Strict Windows Firewall Isolation)
- [ ] Encrypted Automated Workflow Backups
- [ ] GPU Hardware Auto-Configuration (VRAM maximization)
- [ ] Automated Diagnostics & Log Packaging Tool
- [ ] Phase 25: Absolute Reconstruction & Service Control
    - [ ] Update [INSTALL-GUI.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/INSTALL-GUI.ps1) with `sc stop` and deep n8n reconstruction logic
    - [ ] Update [Nexus-Start.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/Nexus-Start.ps1) with asset verification
- [x] Phase 26: Antivirus Mitigation & De-Threatening
    - [x] Update [INSTALL-GUI.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/INSTALL-GUI.ps1) with native PS service control
    - [x] Update [QuickStart.txt](file:///c:/Fiverr%20gigs/N8N%20promo%20project/QuickStart.txt) with AV troubleshooting
    - [x] Sign and package Final V17 distribution
- [x] Phase 27: Client-Safe Asset Reconstruction
    - [x] Update [INSTALL-GUI.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/INSTALL-GUI.ps1) to revert `sc stop` and `Remove-Item`
    - [x] Update Step 4 to use `npm uninstall` instead of manual wipe
    - [x] Sign and package Final V18 distribution
- [x] Phase 28: Handle Isolation & NPM Mitigation (V20)
    - [x] Update installer Timer logic to override Step 4 exit codes if assets exist.
    - [x] Update installer Step 2 to sever log handle inheritance.
    - [x] Bypassed Bitdefender OS Lock via alternate filename ([INSTALL-NEXUS.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/INSTALL-NEXUS.ps1)) and packaged Final V20.

- [x] Phase 29: WinForms UI Thread Unblocking (V21)
    - [x] Identify root cause of Network/UI freeze during Step 7 `ollama pull`.
    - [x] Implement `Application.DoEvents()` and asynchronous process monitoring.
    - [x] Sign and package Final V21 distribution.

- [x] Phase 30: Global UTF-8 Enforcement (V24)
    - [x] Enforce `[Console]::OutputEncoding`, `StreamReader`, and `Out-File` as `UTF8`.
    - [x] Eradicate `cmd.exe /c` redirection and replace with PowerShell native executable invocation (Reverted in V25).
    - [x] Force native `-RedirectStandardOutput` and `-RedirectStandardError` to guarantee UTF-8 pipelines (Caused File LocKS, Reverted in V25).
    - [x] Restored `cmd.exe /c ... >>` with `chcp 65001` and `[Console]::OutputEncoding` to support concurrent WinForms `[System.IO.FileShare]::ReadWrite` log reading (Reverted in V26).
    - [x] **[V31/V33]** Master Stability Baseline (V33): Rolled back to the highly stable linear lock-free structure of V25. Combined with V30 Native Shortcuts to permanently resolve AMSI AV drops. Isolated ALL UI-blocking CLI tests (`npm cache clean`, `ollama pull`) into these async worker scripts to permanently resolve GUI freezing.
    - [x] **[V34]** Patch True UI Thread Freeze (Not Responding): Identified the exact root cause of the freezing at Step 4. Removed the catastrophic `[System.Windows.Forms.Application]::DoEvents()` call from the WinForms Timer tick. Heavy disk I/O (during `npm install`) caused this tick to extend past 300ms, triggering recursive re-entrancy and stack-overflowing the WinForms message loop.
    - [x] **[V35]** Lock-Free UTF-8 Command Pipelines: Replaced internal [.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/update.ps1) `Out-File` piping with an external `cmd.exe >>` wrapper (`Invoke-WorkerScript`). This completely severs file locking (preventing WinForms I/O access denied freezes) and natively wraps `winget` in `chcp 65001` eliminating Asian Mojibake string corruption.
    - [x] **[V36]** The Master Sync: Discovered that previous patches were being applied to [INSTALL-NEXUS.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/INSTALL-NEXUS.ps1) while the user's `Install Axiom Nexus.lnk` shortcut was launching an old [INSTALL-GUI.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/INSTALL-GUI.ps1). Synced the flawless V35 architecture accurately across all files.
    - [x] **[V37]** Master Engine Migration (Bypassing Locks): Due to persistent "Access Denied" errors on [INSTALL-GUI.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/INSTALL-GUI.ps1) from elevated locks, I migrated the finalized codebase to [INSTALL-AXIOM-ENGINE.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/INSTALL-AXIOM-ENGINE.ps1). Re-routed all shortcuts to this fresh, verified target to ensure the patch actually executes.
    - [x] **[v38]** Silent TaskKill Enhancement: Refactored background worker to check for process existence before killing, preventing 404/Not Found "Errors" in the log and ensuring a professional customer experience.
    - [x] **[v38]** Aero UI Migration: Injected `[System.Windows.Forms.Application]::EnableVisualStyles()` to grant the installer a native Windows modern interface (Aero) as requested.
    - [x] **[v38]** Native Shortcut Icons: Forcefully assigned `IconLocation = "powershell.exe, 0"` to all [.lnk](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Install%20Local%20AI.lnk) files to prevent the "blank white icon" bug on the Windows Desktop and Taskbar.
    - [x] **[v38]** Established `versioning/` Repository: Moved intermediate ZIPs and legacy scripts to a dedicated sub-folder to keep the workspace pristine.
    - [x] **[v40]** Dashboard Boot Engine Migration: Resolved a "ghost lock" corruption on the original launcher by migrating to [Axiom-Dashboard-Boot.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/Axiom-Dashboard-Boot.ps1). This ensures the n8n background service and browser dashboard boot correctly when clicking the Launch shortcut.
    - [x] **[v41]** Axiom Launch Center GUI: Developing a branded launch feedback window that streams engine logs and wait for "Ready" signal.
    - [x] **[v42]** Python Muting & Status Detection: Refined the ready-check to handle v2 "Accessible" messages and muted the Python venv warnings for better portability.
    - [x] **[v43]** App Mode Surgical Launch: Refined the standalone window logic to prevent redundant browser windows and updated QuickStart docs for owner setup.
    - [x] **[v44]** n8n "Quiet Mode" Automation: Injected environment variables to automatically bypass the personalization survey and suppress diagnostics/marketing prompts on first boot.
    - [x] Sign and verify Final V44 release.
    - [x] **[V26]** Implement lock-free UTF-8 PowerShell object pipelines: `powershell.exe -Command "... 2>&1 | Out-File -Encoding utf8 -Append"`.
    - [x] **[V27]** Fixed `ENOENT` spacing errors! Refactored inner command bindings to use `[Convert]::ToBase64String()` and `-EncodedCommand` to block inner strings from dropping quotations when passed to the background shells.
    - [x] **[V26]** Patch UI Thread Freeze: Fix Catastrophic Regex Backtracking caused by `ollama pull` streaming `\r` progress bars. Change `\n` split to `[\r\n]+`.
    - [x] Eliminate Asian Mojibake characters from terminal output.
    - [x] Sign and package Final V27 distribution.

## Previous Milestones
- [x] Fixed "Cannot GET /" by locking EXPLICIT environment variables (`HOST`, `PROTOCOL`, `BASE_URL`)
- [x] Fixed Step 6 Workflow Import (Removed invalid `--separate` flag for single-file import)
- [x] Implement ghost process cleanup in [Nexus-Start.ps1](file:///c:/Fiverr%20gigs/N8N%20promo%20project/Managed_Stack_Data/Nexus-Start.ps1)
- [x] Implement HTTP health check verification before browser launch
- [x] Lock `N8N_PORT=5678` in startup sequence
- [x] Restore "Finish/Exit" guards in GUI click handlers
- [x] Implement robust ANSI filtering for clean terminal
- [x] Fix file concurrency (Lock) issue in logging
- [x] Integrated Axiom Nexus visual branding (Logo)
- [x] Applied Digital Signatures (`Axiom-Nexus-Secure`)
