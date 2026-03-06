$base = @{
    name = "Test Workflow"
    nodes = @(
        @{
            id = "test-node"
            name = "Test HTTP"
            type = "n8n-nodes-base.httpRequest"
            typeVersion = 4.2
            position = @(0,0)
            parameters = @{
                method = "POST"
                url = "http://localhost:11434/api/generate"
                sendBody = $true
                specifyBody = "json"
                jsonBody = "={`"model`": `"llama3.2`", `"stream`": false, `"prompt`": `"hi`"}"
                options = @{}
            }
        }
    )
    connections = @{}
    active = $false
    versionId = "db8e3bb3-a5f1-460d-a342-fd82531636c2"
    id = "test_id"
}

@($base) | ConvertTo-Json -Depth 10 | Set-Content "test_http.json"
n8n import:workflow --input="test_http.json" 2>&1
