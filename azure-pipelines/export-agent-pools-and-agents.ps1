$coll = https://tfsserver:8080/tfs/defaultcollection
$apiurl = "$coll/_apis"
$filepath = "C:\temp\agentsandpools.csv"
 
Class AgentPoolEntry {
    [int]$AgentPoolId
    [string]$AgentPoolName
    [int]$AgentId
    [string]$AgentName
    [bool]$AgentEnabled
    [string]$AgentStatus
    [string]$AgentVersion
}
 
function Get-Agents ($poolid)
{
    $uri = "$apiurl/distributedtask/pools/$poolid/agents"
    $response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -UseDefaultCredentials
    $agents = ($response.Content | ConvertFrom-Json).value
    return $agents
}
 
$uri = "$apiurl/distributedtask/pools"
$response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -UseDefaultCredentials
$agentpools = ($response.Content | ConvertFrom-Json).value
 
$agentpoolentries = New-Object System.Collections.ArrayList
foreach ($agentpool in $agentpools)
{
    $agents = Get-Agents -poolid $agentpool.id
    foreach ($agent in $agents)
    {
        $agentpoolentry = New-Object AgentPoolEntry
        $agentpoolentry.AgentPoolId = $agentpool.id
        $agentpoolentry.AgentPoolName = $agentpool.name
        $agentpoolentry.AgentId = $agent.id
        $agentpoolentry.AgentName = $agent.name
        $agentpoolentry.AgentEnabled = $agent.enabled
        $agentpoolentry.AgentStatus = $agent.status
        $agentpoolentry.AgentVersion = $agent.version
        $agentpoolentries.Add($agentpoolentry)
    }
}
 
$agentpoolentries | Export-Csv -Path $filepath -UseCulture
