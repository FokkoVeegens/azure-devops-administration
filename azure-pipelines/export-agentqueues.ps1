# This script will export the agent queue registrations for all Team Projects, so they can be restored after an Azure DevOps Data Import
# Before you run this script, first the Agent Pools need to be restored using its respective scripts.

$ErrorActionPreference = "Stop"

$coll = "http://tfsserver:8080/tfs/DefaultCollection"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$outputfile_queues = "C:\temp\agentqueues.csv"
$outputfile_grants = "C:\temp\agentqueues_grants.csv"

Class AgentQueue {
    [string]$TeamProjectId
    [string]$TeamProjectName
    [int]$PoolId
    [string]$PoolName
    [int]$QueueId
    [string]$QueueName
    [string]$AuthorizeAllPipelines
}

Class AgentQueueGrants {
    [int]$QueueId
    [int]$PipelineId
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

function Get-AgentPools()
{
    Get-JsonOutput -uri "$coll/_apis/distributedtask/pools" -usevalueproperty $true
}

function Get-AgentQueues($teamproject)
{
    return Get-JsonOutput -uri "$coll/$teamproject/_apis/distributedtask/queues"
}

function Get-PipelineQueuePermissions($teamproject, $queueid)
{
    return Get-JsonOutput -uri "$coll/$teamproject/_apis/pipelines/pipelinePermissions/queue/$queueid" -usevalueproperty $false
}

$teamprojects = Get-TeamProjects
$queuesexport = New-Object System.Collections.ArrayList
$grantsexport = New-Object System.Collections.ArrayList
$agentpools = Get-AgentPools
foreach ($teamproject in $teamprojects)
{
    Write-Host "Processing Team Project '$($teamproject.name)'"
    $queues = Get-AgentQueues -teamproject $teamproject.name
    foreach ($queue in $queues)
    {
        Write-Host "Processing Queue '$($queue.name)' with id $($queue.id)"
        if ($queueobject.pool.isHosted)
        {
            Write-Host "Skipping because the queue is hosted" -ForegroundColor Yellow
            continue
        }

        $agentpool = $agentpools | Where-Object { $_.id -eq $queue.pool.id }
        if (!$agentpool)
        {
            Write-Host "Pool for queue not found! Queue will be skipped." -ForegroundColor Red
            continue
        }

        # Get permissions for queue:
        # * queue level (all pipelines true/false)
        # * pipeline level (specific pipelines)
        $pipelineQueuePermissions = Get-PipelineQueuePermissions -teamproject $teamproject.name -queueid $queue.id

        # Get specific pipeline permissions
        foreach ($pipelinepermission in $pipelineQueuePermissions.pipelines)
        {
            $agentQueueGrantsObject = New-Object AgentQueueGrants
            $agentQueueGrantsObject.QueueId = $queue.id
            $agentQueueGrantsObject.PipelineId = $pipelinepermission.id
            $grantsexport.Add($agentQueueGrantsObject)
        }

        $queueobject = New-Object AgentQueue
        $queueobject.TeamProjectId = $teamproject.id
        $queueobject.TeamProjectName = $teamproject.name
        $queueobject.PoolId = $queue.pool.id
        $queueobject.PoolName = $queue.pool.name
        $queueobject.QueueId = $queue.id
        $queueobject.QueueName = $queue.name

        # Queue-level permissions (authorize all pipelines true/false)
        $queueobject.AuthorizeAllPipelines = $false
        if ($pipelineQueuePermissions.allPipelines)
        {
            $queueobject.AuthorizeAllPipelines = $pipelineQueuePermissions.allPipelines.authorized
        }
        $queuesexport.Add($queueobject) | Out-Null
    }
    
}

$queuesexport | Export-Csv -Path $outputfile_queues -UseCulture
$grantsexport | Export-Csv -Path $outputfile_grants -UseCulture
