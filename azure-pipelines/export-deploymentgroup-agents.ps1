$ErrorActionPreference = "Stop"

$coll = "http://tfsserver:8080/tfs/DefaultCollection"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$outputfile = "C:\temp\deploymentgroup_agents.csv"

Class Agent {
    [string]$TeamProject
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

function Get-TeamProjects ()
{
    return Get-JsonOutput -uri "$coll/_apis/projects"
}

function Get-DeploymentPools ($teamproject)
{
    return Get-JsonOutput -uri "$coll/$teamproject/_apis/distributedtask/deploymentgroups"
}

function Get-Agents ($poolid)
{
    return Get-JsonOutput -uri "$coll/_apis/distributedtask/pools/$poolid/agents?includeCapabilities=true"
}

$teamprojects = Get-TeamProjects
$agentsarray = New-Object System.Collections.ArrayList
foreach ($teamproject in $teamprojects)
{
    Write-Host "Processing Team Project '$($teamproject.name)'"
    $deploymentPools = Get-DeploymentPools -teamproject $teamproject.name
    foreach ($deploymentPool in $deploymentPools)
    {
        Write-Host "Processing pool '$($deploymentPool.pool.name)'"
        $agents = Get-Agents -poolid $deploymentPool.pool.id
        foreach ($agent in $agents)
        {
            $agentobject = New-Object Agent
            $agentobject.TeamProject = $teamproject.name
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
}


$agentsarray | Export-Csv -Path $outputfile -UseCulture
