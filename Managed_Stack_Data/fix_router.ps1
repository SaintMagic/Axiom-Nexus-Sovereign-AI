$json = Get-Content -Raw "Axiom-Master-Router.json" | ConvertFrom-Json

foreach ($node in $json[0].nodes) {
    if ($node.type -eq "n8n-nodes-base.switch") {
        # Upgrade version
        $node.typeVersion = 3.4
        
        $newValues = @()
        foreach ($val in $node.parameters.rules.values) {
            $newConds = @()
            foreach ($cond in $val.conditions.conditions) {
                $newConds += @{
                    id = [guid]::NewGuid().ToString()
                    leftValue = $cond.leftValue
                    rightValue = $cond.rightValue
                    operator = @{
                        type = "string"
                        operation = "equals"
                    }
                }
            }
            
            $newValues += @{
                conditions = @{
                    options = @{
                        caseSensitive = $true
                        leftValue = ""
                        typeValidation = "strict"
                        version = 3
                    }
                    conditions = $newConds
                    combinator = $val.conditions.combinator
                }
                renameOutput = $false
                outputIndex = $val.outputIndex
            }
        }
        
        $node.parameters = @{
            mode = "rules"
            rules = @{ values = $newValues }
            looseTypeValidation = $false
            options = @{}
        }
    }
}

$json | ConvertTo-Json -Depth 10 | Set-Content "Axiom-Master-Router.json"
Get-Content "Axiom-Master-Router.json" | Set-Clipboard
