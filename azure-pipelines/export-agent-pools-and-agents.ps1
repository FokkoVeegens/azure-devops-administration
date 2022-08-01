$coll = "https://dev.azure.com/YOURORG"
$filepath = "C:\temp\agentsandpools.csv"
$pat = Get-Content -Path ".\pat.txt"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}
$apiurl = "$coll/_apis"
 
Class AgentPoolEntry {
    [int]$AgentPoolId
    [string]$AgentPoolName
    [int]$AgentId
    [string]$AgentName
    [bool]$AgentEnabled
    [string]$AgentStatus
    [string]$AgentVersion
    [string]$AgentHomeDirectory
    [string]$AgentUserDomain
    [string]$AgentUserName
    [string]$AgentComputerName
    [string]$AgentOS
}
 
function Get-Agents ($poolid)
{
    $uri = "$apiurl/distributedtask/pools/$poolid/agents?includeCapabilities=true"
    $response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $header
    $agents = ($response.Content | ConvertFrom-Json).value
    return $agents
}

function Get-Pools ()
{
    $uri = "$apiurl/distributedtask/pools"
    $response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $header
    $agentpools = ($response.Content | ConvertFrom-Json).value  
    return $agentpools
}

$agentpools = Get-Pools
 
$agentpoolentries = New-Object System.Collections.ArrayList
foreach ($agentpool in $agentpools)
{
    Write-Host "Processing pool '$($agentpool.name)'"
    if ($agentpool.isHosted)
    {
        Write-Host "Skipping pool, because it is Microsoft-hosted"
        continue
    }
    $agents = Get-Agents -poolid $agentpool.id
    foreach ($agent in $agents)
    {
        Write-Host "  Processing agent '$($agent.name)'"
        $agentpoolentry = New-Object AgentPoolEntry
        $agentpoolentry.AgentPoolId = $agentpool.id
        $agentpoolentry.AgentPoolName = $agentpool.name
        $agentpoolentry.AgentId = $agent.id
        $agentpoolentry.AgentName = $agent.name
        $agentpoolentry.AgentEnabled = $agent.enabled
        $agentpoolentry.AgentStatus = $agent.status
        $agentpoolentry.AgentVersion = $agent.version
        $agentpoolentry.AgentHomeDirectory = $agent.systemCapabilities.'Agent.HomeDirectory'
        $agentpoolentry.AgentUserDomain = $agent.systemCapabilities.USERDOMAIN
        $agentpoolentry.AgentUserName = $agent.systemCapabilities.USERNAME
        $agentpoolentry.AgentComputerName = $agent.systemCapabilities.COMPUTERNAME
        $agentpoolentry.AgentOS = $agent.systemCapabilities.'Agent.OS'
        $agentpoolentries.Add($agentpoolentry) | Out-Null
    }
}

Write-Host "Writing CSV file"
$agentpoolentries | Export-Csv -Path $filepath -UseCulture
Write-Host "Done"
