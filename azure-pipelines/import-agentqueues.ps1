# Will restore Agent Queues in all Team projects as part of the Azure DevOps Data Import
# First run export-agentqueues.ps1 to create the input files
# This script randomly fails with the following error message. I have not found the issue. Running it multiple times will finish the import
# {"$id":"1","innerException":null,"message":"TF400898: An Internal Error Occurred. Activity Id:
# 13ece649-73db-4b53-a501-6598b03e7f0d.","typeName":"System.Web.Http.HttpResponseException,
# System.Web.Http","typeKey":"HttpResponseException","errorCode":0,"eventId":0}

$ErrorActionPreference = "Stop"

$org = "https://dev.azure.com/YOURORG"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$inputfile_queues = "C:\Temp\agentqueues.csv"
$inputfile_grants = "C:\Temp\agentqueues_grants.csv"

Class AgentQueue {
    [string]$TeamProjectId
    [string]$TeamProjectName
    [int]$PoolId
    [string]$PoolName
    [int]$QueueId
    [string]$QueueName
    [string]$AuthorizeAllPipelines
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

function Invoke-RestPost ($uri, $body, [bool]$usevalueproperty = $true)
{
    $output = (Invoke-WebRequest -Uri $uri -Method POST -ContentType "application/json" -Body $body -Headers $header ) | ConvertFrom-Json
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Invoke-RestPatch ($uri, $body, [bool]$usevalueproperty = $true)
{
    $output = (Invoke-WebRequest -Uri $uri -Method PATCH -ContentType "application/json-patch+json" -Body $body -Headers $header ) | ConvertFrom-Json
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
    return Get-JsonOutput -uri "$org/_apis/projects"
}

function Get-AgentQueuesByProject($teamproject)
{
    return Get-JsonOutput -uri "$org/$teamproject/_apis/distributedtask/queues"
}

function Get-AgentQueues()
{
    $teamprojects = Get-TeamProjects
    $allqueues = New-Object System.Collections.ArrayList
    foreach ($teamproject in $teamprojects)
    {
        $queues = Get-AgentQueuesByProject -teamproject $teamproject.name
        foreach ($queue in $queues)
        {
            $queueobject = New-Object AgentQueue
            $queueobject.TeamProjectId = $teamproject.id
            $queueobject.TeamProjectName = $teamproject.name
            $queueobject.PoolId = $queue.pool.id
            $queueobject.PoolName = $queue.pool.name
            $queueobject.QueueId = $queue.id
            $queueobject.QueueName = $queue.name
            $allqueues.Add($queueobject) | Out-Null
        }
    }
    return $allqueues
    
}

function Get-AgentPools()
{
    Get-JsonOutput -uri "$org/_apis/distributedtask/pools" -usevalueproperty $true
}

function Add-AgentQueue($teamprojectname, $poolid, $name, $authorizeAllPipelines)
{
    $body = @"
{
    "name": "$($name)",
    "pool": {
        "id": "$($poolid)"
    }
}
"@
    $queue = Invoke-RestPost -uri "$org/$teamprojectname/_apis/distributedtask/queues?authorizePipelines=$($authorizeAllPipelines)&api-version=7.1-preview.1" -body $body -usevalueproperty $false
    return $queue
}

function Add-PipelinePermission ($teamproject, $queueid, $pipelineid)
{
    $body = @"
{
    "pipelines": [
        {
            "id": "$($pipelineid)",
            "authorized": true
        }
    ]
}
"@
    return Invoke-RestPatch -uri "$org/$teamproject/_apis/pipelines/pipelinePermissions/queue/$($queueid)?api-version=7.1-preview.1" -body $body -usevalueproperty $false
}

$queuesintarget = Get-AgentQueues
$queuesinfile = Import-Csv -Path $inputfile_queues -UseCulture
$grantsinfile = Import-Csv -Path $inputfile_grants -UseCulture
$poolsintarget = Get-AgentPools

foreach ($queueinfile in $queuesinfile)
{
    Write-Host "Processing Team Project '$($queueinfile.TeamProjectName)', queue '$($queueinfile.QueueName)'"
    if ($queuesintarget | Where-Object { $_.TeamProjectId -eq $queueinfile.TeamProjectId `
                                            -and $_.PoolName -eq $queueinfile.PoolName `
                                            -and $_.QueueName -eq $queueinfile.QueueName })
    {
        Write-Host "Queue already exists"
        continue
    }
    $newpool = $poolsintarget | Where-Object { $_.name -eq $queueinfile.PoolName }
    $newqueue = ""
    try {
        $newqueue = Add-AgentQueue -teamprojectname $queueinfile.TeamProjectName -poolid $newpool.id -name $queueinfile.QueueName -authorizeAllPipelines $queueinfile.AuthorizeAllPipelines
    }
    catch {
        $errormsg = ($_.ErrorDetails.Message | ConvertFrom-Json).message
        Write-Host "Adding queue returned an error, but it might still have been created; $errormsg" -ForegroundColor Red
    }

    $grantstorestore = $grantsinfile | Where-Object { $_.QueueId -eq $queueinfile.QueueId }
    foreach ($granttorestore in $grantstorestore)
    {
        Add-PipelinePermission -teamproject $queueinfile.TeamProjectName -queueid $queueinfile.QueueId -pipelineid $newqueue.id | Out-Null
    }

    Write-Host "Queue added successfully (old id: $($queueinfile.QueueId), new id: $($newqueue.id))"
}
