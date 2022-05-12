# This script exports all build definitions and all builds to two separate CSV files
# I have built this script to do an analysis of what the new retention policies in Azure DevOps Server 2020 do
# More info on the change can be found here: https://devblogs.microsoft.com/devops/safely-upgrade-from-azure-devops-server-2019-to-server-2020/
# This script is intended to be used on Azure DevOps SERVER installations and not SERVICES (cloud)
# Make sure you change the variables below to suit your own situation
# This script is certainly not optimized for speed of execution, but rather for speed of development

$pat = "EnterYourOwn"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$org = "https://azuredevopsserver/tfs/defaultcollection"
$defsfilepath = "D:\scriptoutput\BuildDefinitions.csv"
$buildsfilepath = "D:\scriptoutput\Builds.csv"

Class BuildDefinition {
    [string]$TeamProject
    [int]$Id
    [string]$Name
    [string]$Branch
    [string]$ArtifactTypesToDelete
    [int]$DaysToKeep
    [int]$MinimumToKeep
    [string]$DeleteBuildRecord
    [string]$DeleteTestResults
}

$outputbuilddefinitions = New-Object System.Collections.ArrayList

Class Build {
    [string]$TeamProject
    [int]$DefinitionId
    [string]$DefinitionName
    [int]$BuildId
    [string]$BuildName
    [datetime]$DateCreated
    [string]$Result
    [string]$RetainedByRelease
    [string]$KeepForever
    [string]$Url
}

$outputbuilds = New-Object System.Collections.ArrayList

function Get-JsonOutput($uri, [bool]$usevalueproperty)
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

function Get-TeamProjects()
{
    return Get-JsonOutput -uri "$org/_apis/projects" -usevalueproperty $true
}

function Get-BuildDefinitions($teamproject)
{
    return Get-JsonOutput -uri "$org/$teamproject/_apis/build/definitions" -usevalueproperty $true
}

function Get-BuildDefinition($teamproject, $id)
{
    return Get-JsonOutput -uri "$org/$teamproject/_apis/build/definitions/$id" -usevalueproperty $false
}

function Get-Builds($teamproject, $definitionid)
{
    return Get-JsonOutput -uri "$org/$teamproject/_apis/build/builds?definitions=$definitionid" -usevalueproperty $true
}

$teamprojects = Get-TeamProjects
foreach ($teamproject in $teamprojects)
{
    $builddefinitions = Get-BuildDefinitions -teamproject $teamproject.name
    foreach ($builddefinition in $builddefinitions)
    {
        Write-Host "Processing Build Definition $($builddefinition.name) in Team Project $($teamproject.name)"

        $builddefinitionfull = Get-BuildDefinition -teamproject $teamproject.name -id $builddefinition.id

        if ($builddefinitionfull.retentionRules.Count -gt 1)
        {
            Write-Host "This definition has multiple retention rules"
        }

        $outputbuilddefinition = New-Object BuildDefinition
        $outputbuilddefinition.TeamProject = $teamproject.name
        $outputbuilddefinition.Id = $builddefinition.id
        $outputbuilddefinition.Name = $builddefinition.name
        $outputbuilddefinition.Branch = ($builddefinitionfull.retentionRules[0].branches -join "|")
        $outputbuilddefinition.ArtifactTypesToDelete = ($builddefinitionfull.retentionRules[0].artifactTypesToDelete -join "|")
        $outputbuilddefinition.DaysToKeep = $builddefinitionfull.retentionRules[0].daysToKeep
        $outputbuilddefinition.MinimumToKeep = $builddefinitionfull.retentionRules[0].minimumToKeep
        $outputbuilddefinition.DeleteBuildRecord = $builddefinitionfull.retentionRules[0].deleteBuildRecord
        $outputbuilddefinition.DeleteTestResults = $builddefinitionfull.retentionRules[0].deleteTestResults
        $outputbuilddefinitions.Add($outputbuilddefinition)

        $builds = Get-Builds -teamproject $teamproject.name -definitionid $builddefinition.id
        foreach ($build in $builds)
        {
            $outputbuild = New-Object Build
            $outputbuild.TeamProject = $teamproject.name
            $outputbuild.DefinitionId = $builddefinition.id
            $outputbuild.DefinitionName = $builddefinition.name
            $outputbuild.BuildId = $build.Id
            $outputbuild.BuildName = $build.buildNumber
            $outputbuild.DateCreated = $build.queueTime
            $outputbuild.Result = $build.result
            $outputbuild.RetainedByRelease = $build.retainedByRelease
            $outputbuild.KeepForever = $build.keepForever
            $outputbuild.Url = $build.url
            $outputbuilds.Add($outputbuild)            
        }

    }
}

$outputbuilddefinitions | Export-Csv -Path $defsfilepath -UseCulture
$outputbuilds | Export-Csv -Path $buildsfilepath -UseCulture
