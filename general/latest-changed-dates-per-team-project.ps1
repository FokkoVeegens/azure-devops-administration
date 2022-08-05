# This script exports the most recent activity per Team Project. 
# It outputs a CSV file containing dates on which the latest change of every functional part of a Team Project as been executed.
# The CSV file can be used in Excel to make a comprehensive overview
# It also outputs a log file in which details can be found on what resources contain the latest change.
# Don't forget to enter your own Azure DevOps Organization name and to have a pat.txt file next to this script, containing a Personal Access Token, having access to all scopes!

# Notes:
# * This script is not optimized to run in very big environments! Please use it with care!
# * Test case changes are visible through work item changes

# TODO/NOT YET IMPLEMENTED: 
# * Dashboards (lacks changed date in REST API)
# * Wiki comments (low priority)
# * Delivery Plans (lacks changed date in REST API)
# * Deployment groups (lacks changed date in REST API)
# * Artifacts (lacks changed date in REST API)

$ErrorActionPreference = "Stop"

$org = "YourAzureDevopsOrgName" # Azure DevOps Organization (exclude https://dev.azure.com/)
$logfilepath = "C:\temp\logfile.txt" # Path to the Text log file containing log data about the run
$outputfilepath = "C:\temp\azdoactivity.csv" # Path to the CSV file containing the output
$selectedteamproject = "" # Enter a Team Project name to execute the script for one Team Project instead of all Team Projects

$coll = "https://dev.azure.com/$org"
$rmcoll = "https://vsrm.dev.azure.com/$org"
$pat = Get-Content -Path ".\pat.txt"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}
[DateTime]$mindate = Get-Date -Year 1900 -Month 1 -Day 1 -Hour 12 -Minute 0 -Second 0

Class DateNamePair
{
    [datetime]$Date
    [string]$Name
}

Class PipelineResult
{
    [datetime]$LastChangeDate
    [string]$LastChangeName
    [datetime]$LastRunDate
    [string]$LastRunName
}

Class TeamProjectDates
{
    [string]$TeamProjectName
    [datetime]$Wiki
    [datetime]$WorkItems
    [datetime]$WorkItemQueries
    [datetime]$Tfvc
    [datetime]$Git
    [datetime]$PipelinesDesign
    [datetime]$PipelinesRun
    [datetime]$ReleaseDesign
    [datetime]$ReleaseRun
    [datetime]$Taskgroups
    [datetime]$VariableGroups
    [datetime]$SecureFiles
    [datetime]$TestPlans
    [datetime]$TestSuites
    [datetime]$TestRuns
}

function Write-Log([string]$Message, [ValidateSet("I", "W", "E")]$Level = "I", [switch]$WriteToHost) {
    $levelName = [string]::Empty
    switch ($Level) {
        "I" { $levelName = "INFO"; break }
        "W" { $levelName = "WARN"; break }
        "E" { $levelName = "ERROR"; break }
    }
    $logtime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$logtime`t$levelName`t$Message" | Out-File -FilePath $logfilepath -Append
    if ($WriteToHost)
    {
        Write-Host "$logtime [$levelName] $Message"
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

function Get-Wiki ($teamproject)
{
    return Get-JsonOutput -uri "$coll/$teamproject/_apis/wiki/wikis"
}

function Get-WikiChangedDate ($teamproject)
{
    $wikis = Get-Wiki -teamproject $teamproject
    $result = New-Object -TypeName DateNamePair -Property @{ Date = $mindate; Name = "" }
    foreach ($wiki in $wikis)
    {
        $commits = Get-JsonOutput -uri "$coll/$teamproject/_apis/git/repositories/$($wiki.repositoryId)/Commits"
        $latestcommit = $commits | Sort-Object { [datetime]$_.committer.date } | Select-Object -Last 1
        if ($latestcommit.committer.date -gt $result.Date)
        {
            $result.Date = $latestcommit.committer.date
            $result.Name = "$($wiki.name) ($($wiki.type))"
        }
    }
    return $result
}

function Get-LatestWorkItemChange ($teamproject)
{
    $body = "{ 'query': 'select [System.ChangedDate] from WorkItems where [System.TeamProject] = `"$($teamproject)`" order by [System.ChangedDate] DESC' }"
    $queryresult = Invoke-RestPost -uri "$coll/$teamproject/_apis/wit/wiql?`$top=1&api-version=7.1-preview.2" -body $body -usevalueproperty $false
    if ($queryresult.workItems.count -gt 0)
    {
        $workitemid = $queryresult.workItems[0].id
        $workitem = Get-JsonOutput -uri "$coll/$teamproject/_apis/wit/workitems/$($workitemid)?fields=System.ChangedDate" -usevalueproperty $false
        return $workitem.fields.'System.ChangedDate'        
    }
    else 
    {
        return $mindate
    }
}

function Get-LatestQueryDate ($hierarchy, [datetime]$latestdate)
{
    $currentlatestdate = $latestdate
    foreach ($item in $hierarchy)
    {
        if ($item.isFolder -eq "true" -and $item.name -eq "My Queries")
        {
            continue
        }
        if ($item.isFolder -eq "true" -and $item.hasChildren -eq "true")
        {
            $currentlatestdate = Get-LatestQueryDate -hierarchy $item.Children -latestdate $currentlatestdate
        }
        else 
        {
            if ([datetime]$item.lastModifiedDate -gt $currentlatestdate)
            {
                $currentlatestdate = [datetime]$item.lastModifiedDate
            }
        }

    }
    return $currentlatestdate
}

function Get-LatestQueryChange ($teamproject)
{
    $queries = Get-JsonOutput -uri "$coll/$teamproject/_apis/wit/queries?`$depth=2"
    return Get-LatestQueryDate -hierarchy $queries -latestdate $mindate
}

function Get-LatestTfvcChanges ($teamproject)
{
    $items = Get-JsonOutput -uri "$coll/$teamproject/_apis/tfvc/items?recursionLevel=None" -usevalueproperty $false
    if ($items.count -ne "0")
    {
        $changes = Get-JsonOutput -uri "$coll/$teamproject/_apis/tfvc/changesets?`$top=1&`$orderby=id desc"
        return $changes[0].createdDate
    }
    else 
    {
        return $mindate
    }
}

function Get-LatesGitRepoPush ($repoid)
{
    $result = Get-JsonOutput -uri "$coll/_apis/git/repositories/$repoid/pushes?`$top=1"
    if ($result)
    {
        return $result.date
    }
    else 
    {
        return $mindate
    }
}

function Get-LatestGitChange ($teamproject)
{
    $repos = Get-JsonOutput -uri "$coll/$teamproject/_apis/git/repositories"
    [datetime]$lastrepochange = $mindate
    $repocontaininglatestchange = ""
    foreach ($repo in $repos)
    {
        [datetime]$latestgitrepopush = Get-LatesGitRepoPush -teamproject $teamproject -repoid $repo.id
        if ($latestgitrepopush -gt $lastrepochange)
        {
            $lastrepochange = $latestgitrepopush
            $repocontaininglatestchange = $repo.name
        }
    }
    return (New-Object -TypeName DateNamePair -Property @{ Date = $lastrepochange; Name = $repocontaininglatestchange } )
}

function Get-Pipelines ($teamproject)
{
    return (Get-JsonOutput -uri "$coll/$teamproject/_apis/pipelines")
}

function Get-Pipeline ($id)
{
    return (Get-JsonOutput -uri "$coll/$teamproject/_apis/pipelines/$id" -usevalueproperty $false)
}

function Get-PipelineRuns ($id)
{
    return (Get-JsonOutput -uri "$coll/$teamproject/_apis/pipelines/$id/runs")
}

function Get-LatestPipelineChange ($teamproject)
{
    $pipelines = Get-Pipelines -teamproject $teamproject
    $result = New-Object PipelineResult
    $result.LastChangeDate = $mindate
    $result.LastRunDate = $mindate
    foreach ($pipeline in $pipelines) 
    {
        $pipelineinfo = Get-Pipeline -id $pipeline.id
        if ($pipelineinfo.configuration.designerJson.createdDate -gt $result.LastChangeDate)
        {
            $result.LastChangeDate = $pipelineinfo.configuration.designerJson.createdDate
            $result.LastChangeName = $pipeline.name
        }
        $runs = Get-PipelineRuns -id $pipeline.id
        if ($runs)
        {
            if ($runs[0].createdDate -gt $result.LastRunDate)
            {
                $result.LastRunDate = $runs[0].createdDate
                $result.LastRunName = $runs[0].name
            }            
        }

    }
    return $result
}

function Get-LatestReleaseChange ($teamproject)
{
    $releases = Get-JsonOutput -uri "$rmcoll/$teamproject/_apis/release/definitions"
    if ($releases)
    {
        $lastchanged = $releases | Sort-Object { [datetime]$_.modifiedOn } | Select-Object -Last 1
        return (New-Object -TypeName DateNamePair -Property @{ Date = $lastchanged.modifiedOn; Name = $lastchanged.name } )
    }
    else 
    {
        return (New-Object -TypeName DateNamePair -Property @{ Date = $mindate; Name = "" })
    }
}

function Get-LatestDeploymentDate ($teamproject)
{
    $deployment = Get-JsonOutput -uri "$rmcoll/$teamproject/_apis/release/deployments?queryOrder=descending&`$top=1"
    if ($deployment)
    {
        return (New-Object -TypeName DateNamePair -Property @{ Date = $deployment.queuedOn; Name = "$($deployment.release.name) - $($deployment.releaseDefinition.name)" } )
    }
    else 
    {
        return (New-Object -TypeName DateNamePair -Property @{ Date = $mindate; Name = "" })
    }
}

function Get-GenericLastChange ($teamproject, $apipath, $changeddatepropertyname = "modifiedOn", $namepropertyname = "name")
{
    $objects = Get-JsonOutput -uri "$coll/$teamproject/_apis/$apipath"
    $lastchanged = $objects | Sort-Object { [datetime]$_."$changeddatepropertyname" } | Select-Object -Last 1
    if ($lastchanged)
    {
        return (New-Object -TypeName DateNamePair -Property @{ Date = $lastchanged."$changeddatepropertyname"; Name = $lastchanged."$namepropertyname" } )
    }
    else 
    {
        return (New-Object -TypeName DateNamePair -Property @{ Date = $mindate; Name = "" })
    }
}

function Get-LatestTestSuitesChange ($teamproject)
{
    $testplans = Get-JsonOutput -uri "$coll/$teamproject/_apis/testplan/plans"
    $result = New-Object -TypeName DateNamePair
    foreach ($testplan in $testplans)
    {
        $suitelastchanged = Get-GenericLastChange -teamproject $teamproject -apipath "testplan/Plans/$($testplan.id)/suites?asTreeView=false&expand=children" -changeddatepropertyname "lastUpdatedDate"
        if ($suitelastchanged.Date -gt $result.Date)
        {
            $result = $suitelastchanged
            $result.Name += " - $($testplan.name)"
        }
    }
    return $result
}

$teamprojects = Get-JsonOutput -uri "$coll/_apis/projects"
$results = New-Object System.Collections.ArrayList

if ($selectedteamproject.Length -gt 0)
{
    $teamprojects = $teamprojects | Where-Object { $_.name -eq $selectedteamproject }
}

foreach ($teamproject in $teamprojects)
{
    $item = New-Object -TypeName TeamProjectDates
    $item.TeamProjectName = $teamproject.name
    Write-Log "Processing Team Project: $($teamproject.name)" -WriteToHost

    $latest = Get-WikiChangedDate -teamproject $teamproject.name
    Write-Log "Last changed Wiki: $($latest.Name)"
    $item.Wiki = $latest.Date.ToLocalTime()

    $item.WorkItems = (Get-LatestWorkItemChange -teamproject $teamproject.name).ToLocalTime()
    $item.WorkItemQueries = (Get-LatestQueryChange -teamproject $teamproject.name).ToLocalTime()
    $item.Tfvc = (Get-LatestTfvcChanges -teamproject $teamproject.name).ToLocalTime()
    
    $latest = Get-LatestGitChange -teamproject $teamproject.name
    Write-Log "Last changed Git repo: $($latest.Name)"
    $item.Git = $latest.Date

    $latest = Get-LatestPipelineChange -teamproject $teamproject.name
    Write-Log "Last changed Pipeline: $($latest.LastChangeName)"
    Write-Log "Last run Pipeline: $($latest.LastRunName)"
    $item.PipelinesDesign = $latest.LastChangeDate.ToLocalTime()
    $item.PipelinesRun = $latest.LastRunDate.ToLocalTime()

    $latest = Get-LatestReleaseChange -teamproject $teamproject.name
    Write-Log "Last changed Release definition: $($latest.Name)"
    $item.ReleaseDesign = $latest.Date.ToLocalTime()

    $latest = Get-LatestDeploymentDate -teamproject $teamproject.name
    Write-Log "Last deployed Release: $($latest.Name)"
    $item.ReleaseRun = $latest.Date.ToLocalTime()

    $latest = Get-GenericLastChange -teamproject $teamproject.name -apipath "distributedtask/taskgroups"
    Write-Log "Last changed Taskgroup: $($latest.Name)"
    $item.Taskgroups = $latest.Date.ToLocalTime()

    $latest = Get-GenericLastChange -teamproject $teamproject.name -apipath "distributedtask/variablegroups"
    Write-Log "Last changed Variable Group: $($latest.Name)"
    $item.VariableGroups = $latest.Date.ToLocalTime()

    $latest = Get-GenericLastChange -teamproject $teamproject.name -apipath "distributedtask/securefiles"
    Write-Log "Last changed Secure File: $($latest.Name)"
    $item.SecureFiles = $latest.Date.ToLocalTime()

    $latest = Get-GenericLastChange -teamproject $teamproject.name -apipath "testplan/plans?includePlanDetails=true" -changeddatepropertyname "updatedDate"
    Write-Log "Last changed Test Plan: $($latest.Name)"
    $item.TestPlans = $latest.Date.ToLocalTime()

    $latest = Get-LatestTestSuitesChange -teamproject $teamproject.name
    Write-Log "Last changed Test Suite: $($latest.Name)"
    $item.TestSuites = $latest.Date.ToLocalTime()

    $latest = Get-GenericLastChange -teamproject $teamproject.name -apipath "test/runs/?automated=false&includeRunDetails=true" -changeddatepropertyname "startedDate"
    Write-Log "Last test run: $($latest.Name)"
    $item.TestRuns = $latest.Date.ToLocalTime()

    $results.Add($item) | Out-Null
}

$results | Export-Csv -Path $outputfilepath -UseCulture
