$base = @{
    name = "Test Workflow"
    nodes = @()
    connections = @{}
    active = $false
    versionId = "db8e3bb3-a5f1-460d-a342-fd82531636c2"
    id = "test_id"
}

$nodes = (Get-Content -Raw "Axiom-Master-Router.json" | ConvertFrom-Json)[0].nodes

# Test empty
$base | ConvertTo-Json -Depth 10 | Set-Content "test_import.json"
Write-Host "Testing Empty..."
n8n import:workflow --input="test_import.json" | Out-Null
Write-Host "Empty OK."

foreach ($node in $nodes) {
    Write-Host "Testing Node: $($node.name)"
    $base.nodes = @($node)
    
    # Needs to be wrapped in an array for CLI import
    @($base) | ConvertTo-Json -Depth 10 | Set-Content "test_import.json"
    
    $result = n8n import:workflow --input="test_import.json" 2>&1
    if ($result -like "*Error*") {
        Write-Host "FAILED ON NODE: $($node.name)"
        Write-Host $result
        break
    } else {
        Write-Host "Node $($node.name) OK."
        # Cleanup
        n8n delete:workflow --id="test_id" | Out-Null
    }
}
