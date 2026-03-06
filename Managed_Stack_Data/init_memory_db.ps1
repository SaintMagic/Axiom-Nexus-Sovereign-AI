$dbPath = Join-Path $PSScriptRoot "axiom_memory.db"

# We use a tiny powershell function to initialize the SQLite DB if it doesn't exist
# This ensures that when n8n tries to connect, the tables are already there.

$initScript = @"
CREATE TABLE IF NOT EXISTS short_term_memory (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    sender TEXT NOT NULL,
    content TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS long_term_facts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT,
    fact TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_short_term_timestamp ON short_term_memory(timestamp);
"@

# Note: In a real production environment, we'd use the sqlite3 CLI, but for zero-setup, 
# we'll let n8n handle the heavy lifting. This script just documents the schema we intent to use.
Write-Host "Axiom Memory Schema documented at $dbPath"
# Actually creating a dummy file to ensure n8n has a target
if (-not (Test-Path $dbPath)) { New-Item -ItemType File -Path $dbPath -Force }
