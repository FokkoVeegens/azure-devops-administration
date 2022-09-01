# This script will export all Team Project Collection pipelines, indicating whether they are classic or YAML pipelines
# It will also indicate whether there are multiple stages and whether different agents in one pipeline are used
# It will also export the designerJson property of the pipeline (when it's a classic pipeline), so it can be updated and republished to Azure DevOps
# I use this script to update Agent Pools after a migration from on-prem Azure DevOps Server to cloud Azure DevOps Services (pools get deleted in this process)

$ErrorActionPreference = "Stop"

$coll = "http://tfsserver:8080/tfs/defaultcollection"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$exportfilepath = "C:\Temp\pipelines.csv"
$jsonpath = "C:\Temp\pipelinedefinitions"

Class Pipeline {
    [int]$Id
    [string]$Name
    [string]$Type
    [string]$TeamProject
    [string]$Path
    [int]$NumberOfPhases
    [bool]$HasPhaseWithNotInheritedPool
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

function Get-Pipelines ($teamproject)
{
    return Get-JsonOutput -uri "$coll/$teamproject/_apis/pipelines"
}

function Get-Pipeline ($teamproject, $id)
{
    return Get-JsonOutput -uri "$coll/$teamproject/_apis/pipelines/$id" -usevalueproperty $false
}

if (!(Test-Path -Path $jsonpath))
{
    New-Item -Path $jsonpath -ItemType Directory
}

$teamprojects = Get-TeamProjects
$pipelinesexport = New-Object System.Collections.ArrayList
foreach ($teamproject in $teamprojects)
{
    $pipelines = Get-Pipelines -teamproject $teamproject.name
    foreach ($pipeline in $pipelines)
    {
        $pipelinedetails = Get-Pipeline -teamproject $teamproject.name -id $pipeline.id
        $pipelineobject = New-Object Pipeline
        $pipelineobject.Id = $pipelinedetails.Id
        $pipelineobject.Name = $pipelinedetails.name
        $pipelineobject.Type = $pipelinedetails.configuration.type
        $pipelineobject.TeamProject = $teamproject.name
        $pipelineobject.Path = $pipelinedetails.folder
        $pipelineobject.HasPhaseWithNotInheritedPool = $false

        if ($pipelinedetails.configuration.type -eq "designerJson")
        {
            $json = $pipelinedetails.configuration.designerJson | ConvertTo-Json
            Set-Content -Value $json -Path "$jsonpath\$($pipelinedetails.id).json"
            $pipelineobject.NumberOfPhases = $pipelinedetails.configuration.designerJson.process.phases.Count
            if ($pipelineobject.NumberOfPhases -gt 1)
            {
                foreach($phase in $pipelinedetails.configuration.designerJson.process.phases)
                {
                    if ($phase.target.queue)
                    {
                        $pipelineobject.HasPhaseWithNotInheritedPool = $true
                        break
                    }
                }
            }
        }
        $pipelinesexport.Add($pipelineobject) | Out-Null
    }
}

$pipelinesexport | Export-Csv -Path $exportfilepath -UseCulture
