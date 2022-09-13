$ErrorActionPreference = "Stop"

$coll = "http://tfsserver:8080/tfs/DefaultCollection"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$outputfile = "C:\temp\deploymentgroup_agents.csv"

Class Agent {
    [int]$PoolId
    [string]$PoolName
    [string]$AgentName
    [bool]$AgentEnabled
    [string]$AgentStatus
    [string]$AgentComputerName
    [string]$AgentHomeDirectory
    [string]$AgentUsername
    [string]$AgentUserdomain
}

function Get-JsonOutput($uri, [bool]$usevalueproperty = $true)
{
    $output = (invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $header) | ConvertFrom-Json
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Get-DeploymentPools ()
{
    return Get-JsonOutput -uri "$coll/_apis/distributedtask/deploymentPools/deploymentPoolsSummary"
}

function Get-Agents ($poolid)
{
    return Get-JsonOutput -uri "$coll/_apis/distributedtask/pools/$poolid/agents?includeCapabilities=true"
}

$deploymentPools = Get-DeploymentPools
$agentsarray = New-Object System.Collections.ArrayList
foreach ($deploymentPool in $deploymentPools)
{
    Write-Host "Processing pool '$($deploymentPool.pool.name)'"
    if ($deploymentPool.onlineAgentsCount -eq 0)
    {
        Write-Host "Skipping pool, no online agents"
        continue
    }
    $agents = Get-Agents -poolid $deploymentPool.pool.id
    foreach ($agent in $agents)
    {
        $agentobject = New-Object Agent
        $agentobject.PoolId = $deploymentPool.pool.id
        $agentobject.PoolName = $deploymentPool.pool.name
        $agentobject.AgentName = $agent.name
        $agentobject.AgentEnabled = $agent.enabled
        $agentobject.AgentStatus = $agent.status
        $agentobject.AgentComputerName = $agent.systemCapabilities.'Agent.ComputerName'
        $agentobject.AgentHomeDirectory = $agent.systemCapabilities.'Agent.HomeDirectory'
        $agentobject.AgentUsername = $agent.systemCapabilities.USERNAME
        $agentobject.AgentUserdomain = $agent.systemCapabilities.USERDOMAIN
        $agentsarray.Add($agentobject) | Out-Null
    }
}

$agentsarray | Export-Csv -Path $outputfile -UseCulture
