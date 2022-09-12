# This script will fix the links to the queues and agent pools after an Azure DevOps Data Import (onprem to the cloud migration)
# First the pools and queues will need to be recreated using their respective scripts
# export-pipelines.ps1 needs to be run first on the on-prem environment. This will provide the input files for this script.
# I know, it's not the most beautiful script I've written. Maybe I'll refactor someday. Otherwise I'm open to pull requests ;-)

$ErrorActionPreference = "Stop"

$org = "https://dev.azure.com/YOURORG"
$oldurl = "http://tfsserver:8080/tfs/DefaultCollection"
$oldurlencoded = "http://tfsserver:8080/tfs/DefaultCollection" # only useful when a space exists in the collection name
$pipelineUpdateComment = "Fix the build queue/pool after migration from Azure DevOps Server to Azure DevOps Services"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }

$importfilepath = "C:\Temp\pipelines.csv"
$logfilepath = "C:\temp\import-pipelines-log.txt"
$jsonpath = "C:\Temp\pipelinedefinitions"
$pools = ""
$queues = New-Object System.Collections.ArrayList

Class Queue {
    [string]$TeamProject
    [int]$PoolId
    [int]$QueueId
}

function Write-LogHeader ()
{
    "Time`tLevel`tTeamProject`tPipelineId`tPipelineName`tMessage" | Out-File -FilePath $logfilepath -Append
}

function Write-Log ($level = "INFO", $message, $teamproject, $pipelineid, $pipelinename, [switch]$WriteToHost)
{
    $logtime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$logtime`t$level`t$teamproject`t$pipelineid`t$pipelinename`t$Message" | Out-File -FilePath $logfilepath -Append
    if ($WriteToHost)
    {
        Write-Host "[$level] In '$teamproject', pipeline '$pipelinename' ($pipelineid): $message"
    }
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


function Invoke-RestPut ($uri, $body, [bool]$usevalueproperty = $true)
{
    $output = (Invoke-WebRequest -Uri $uri -Method PUT -ContentType "application/json" -Body $body -Headers $header ) | ConvertFrom-Json
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Get-Pools ()
{
    return Get-JsonOutput -uri "$org/_apis/distributedtask/pools"
}

function Get-Queues ($teamproject)
{
    return Get-JsonOutput -uri "$org/$teamproject/_apis/distributedtask/queues"
}

function Get-PoolsAndQueues ($teamprojects)
{
    # Builds an array with Team Project Name, Agent Pool Id and Agent Queue Id, so a mapping is possible, when Team Project and Pool are known
    foreach ($teamproject in $teamprojects)
    {
        $teamprojectqueues = Get-Queues -teamproject $teamproject.name
        foreach ($teamprojectqueue in $teamprojectqueues)
        {
            $queueobject = New-Object Queue
            $queueobject.TeamProject = $teamproject.name
            $queueobject.PoolId = $teamprojectqueue.pool.id
            $queueobject.QueueId = $teamprojectqueue.id
            $queues.Add($queueobject) | Out-Null
        }
    }
}

function Get-PoolByName ($name)
{
    return ($pools | Where-Object { $_.name -eq $name })
}

function Get-TeamProjects()
{
    return Get-JsonOutput -uri "$org/_apis/projects"
}

function Get-DesignerJson ($teamproject, $pipelineid)
{
    return Get-JsonOutput -uri "$org/$teamproject/_apis/build/definitions/$pipelineid" -usevalueproperty $false
}

function Update-DesignerJson ($teamproject, $pipelineid, $designerJson)
{
    return Invoke-RestPut -uri "$org/$teamproject/_apis/build/definitions/$($pipelineid)?api-version=7.1-preview.7" -body $designerJson -usevalueproperty $false
}

Write-LogHeader

# Get all pools of the new environment
$pools = Get-Pools
$teamprojects = Get-TeamProjects

# Get a mapping between Pools and Queues
Get-PoolsAndQueues -teamprojects $teamprojects

$pipelines = Import-Csv -Path $importfilepath -UseCulture

# Exclude YAML pipelines
$pipelines = $pipelines | Where-Object { $_.Type -eq "designerJson" }
foreach ($pipeline in $pipelines)
{
    Write-Log -level INFO -message "Start update" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name -WriteToHost
    $designerJsonFileName = "$jsonpath\$($pipeline.Id).json"
    if (!(Test-Path -Path $designerJsonFileName))
    {
        Write-Log -level WARN -message "Skipping pipeline because the file does not exist ($($designerJsonFileName))" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
        continue
    }
    $designerJsonFile = Get-Content -Path $designerJsonFileName | ForEach-Object { $_.replace($oldurl, $org).replace($oldurlencoded, $org) } | ConvertFrom-Json -Depth 50
    
    $designerJsonOnline = ""
    try {
        $designerJsonOnline = Get-DesignerJson -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id    
    }
    catch {
        $errorobj = $_.ErrorDetails.Message | ConvertFrom-Json
        Write-Log -level ERROR -message "Retrieval of pipeline from Azure DevOps Services failed (pipeline will not be updated): $($errorobj.message)" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
        if ($errorobj.typeName -notmatch "Microsoft.TeamFoundation.Build.WebApi.DefinitionNotFoundException")
        {
            exit
        }
        else 
        {
            continue
        }
    }

    if ($designerJsonOnline.draftOf)
    {
        Write-Log -level WARN -message "Skipping definition because it is a draft of pipeline id $($designerJsonOnline.draftOf.id)" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
        continue
    }

    $poolname = $designerJsonFile.queue.pool.name
    $poolid = (Get-PoolByName -name $poolname).id
    $oldqueueid = $designerJsonFile.queue.id
    $queue = $queues | Where-Object { $_.TeamProject -eq $pipeline.TeamProject -and $_.PoolId -eq $poolid }

    # Fix JobAuthorizationScope on Root level and phase level (should be the same)
    # 1 = projectCollection = Project Collection
    # 2 = project = Current Project
    $jobAuthorizationScope = "1"
    if ($designerJsonOnline.jobAuthorizationScope -eq "2" -or $designerJsonOnline.jobAuthorizationScope -eq "project")
    {
        $jobAuthorizationScope = "2"
    }
    $designerJsonFile.jobAuthorizationScope = $jobAuthorizationScope

    if (!$queue)
    {
        Write-Log -level WARN -message "Skipping pipeline because the queue for the pool cannot be found" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
        continue
    }
    # Queue is still available online after migration, but just to be sure, I use the one from the exported file
    $designerJsonOnline.queue.pool = ("{ `"id`": $poolid, `"name`":  `"$poolname`" }" | ConvertFrom-Json)
    $designerJsonOnline.queue.id = $queue.QueueId
    $designerJsonOnline.queue._links.self = $designerJsonFile.queue._links.self -replace "Queues/$oldqueueid", "Queues/$($queue.QueueId)"
    $designerJsonOnline.queue.url = $designerJsonFile.queue.url -replace "Queues/$oldqueueid", "Queues/$($queue.QueueId)"

    foreach ($phase in $designerJsonOnline.process.phases)
    {
        $phase.jobAuthorizationScope = $jobAuthorizationScope
        if ($phase.target.queue)
        {
            # phase is the phase in the current online environment
            # We need to retrieve the queue/pool information from the file, beccause it has been removed from the online environment
            # by the data import process
            $filephase = $designerJsonFile.process.phases | Where-Object { $_.refName -eq $phase.refName }
            if (!$filephase)
            {
                Write-Log -level WARN -message "Cannot update phase with refname '$($phase.refName)', because the corresponding phase in the original pipeline cannot be found" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
                continue
            }

            if (!$filephase.target.queue.pool.name)
            {
                Write-Log -level WARN -message "Not updating phase queue/pool, because the pool name is empty" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
                continue
            }

            $phasepoolname = $filephase.target.queue.pool.name
            $phasepoolid = (Get-PoolByName -name $phasepoolid).id
            $phase.target.queue.pool.id = $poolid
            $phaseoldqueueid = $filephase.target.queue.id
            $phasequeue = $queues | Where-Object { $_.TeamProject -eq $pipeline.TeamProject -and $_.PoolId -eq $phasepoolid }
        
            if (!$phasequeue)
            {
                Write-Log -level WARN -message "Skipping pipeline because the queue for pool '$($phasepoolname)' cannot be found" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
                continue
            }

            $phase.target.queue.id = $queue.QueueId
            $phase.target.queue._links.self.href = $designerJsonFile.queue._links.self.href -replace "Queues/$phaseoldqueueid", "Queues/$($phasequeue.id)"
            $phase.target.queue.url = $designerJsonFile.queue.url -replace "Queues/$phaseoldqueueid", "Queues/$($phasequeue.id)"
        }
    }

    if (!(Get-Member -InputObject $designerJsonOnline -Name "comment"))
    {
        Add-Member -InputObject $designerJsonOnline -MemberType NoteProperty -Name "comment" -Value $pipelineUpdateComment
    }
    else {
        $designerJsonOnline.comment = $pipelineUpdateComment    
    }
    try {
        $result = Update-DesignerJson -teamproject $pipeline.TeamProject -pipelineid $pipeline.id -designerJson ($designerJsonOnline | ConvertTo-Json -Depth 50)    
    }
    catch {
        $errormsg = ($_.ErrorDetails.Message | ConvertFrom-Json).message
        Write-Log -level ERROR -message "Update failed with an error: $errormsg" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
        if ($errormsg -notmatch "TF401019" `
                -and $errormsg -notmatch "The pool does not exist or has not been authorized for use" `
                -and $errormsg -notmatch "The pipeline is not valid"`
                -and $errormsg -notlike "*Task group*not found*")
        {
            exit
        }
    }
    
    
    if ($result.revision -le $designerJsonFile.revision)
    {
        Write-Log -level WARN -message "There might be an error; revision of the updated pipeline: $($result.revision), revision of the exported json: $($designerJsonFile.revision)" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
    }
    else {
        Write-Log -level INFO -message "The update was successful" -teamproject $pipeline.TeamProject -pipelineid $pipeline.Id -pipelinename $pipeline.Name
        Rename-Item -Path $designerJsonFileName -NewName ($designerJsonFileName -replace ".json", "_done.json")
    }
}
