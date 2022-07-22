# Will remove all Agent Queues from all Team Projects with a specific name (replace "Azure Pipelines" with the name of the agent queue, unless you want to remove the pipeline registrations of the Microsoft-hosted agents)
# It's possible to exclude 1 Team Project by providing its name to the $projecttoexclude variable
# Ensure you replace MY-DEVOPS-ORGANIZATION with your own
# Ensure you have a pat.txt file containing a valid Personal Access Token in the same dir as this script

$queuetoremove = "Azure Pipelines"
$projecttoexclude = ""
$org = "https://dev.azure.com/MY-DEVOPS-ORGANIZATION"
$pat = Get-Content -Path ".\pat.txt"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}

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

function Invoke-Delete($uri)
{
    $result = invoke-webrequest -Uri $uri -Method DELETE -ContentType "application/json" -Headers $header
    if ($result.statuscode -lt 200 -or $result.statuscode -ge 300)
    {
        Write-Host "Error removing Agent Pool"
    }
    else 
    {
        Write-Host "Success"
    }
}

function Get-TeamProjects()
{
    return Get-JsonOutput -uri "$org/_apis/projects" -usevalueproperty $true
}

function Get-Queues($teamproject)
{
    return Get-JsonOutput -uri "$org/$teamproject/_apis/distributedtask/queues" -usevalueproperty $true
}

function Remove-Queue($teamproject, $queueid)
{
    Invoke-Delete -uri "$org/$teamproject/_apis/distributedtask/queues/$($queueid)?api-version=7.1-preview.1"
}

$projects = Get-TeamProjects
foreach ($project in $projects) 
{
    if ($project.name -eq $projecttoexclude)
    {
        continue
    }
    Write-Host "Team Project: $($project.name)"
    $queues = Get-Queues -teamproject $project.name
    $queue = $queues | Where-Object { $_.name -eq $queuetoremove }
    if ($queue)
    {
        Write-Host "Removing queue: $($queue.name)"
        Remove-Queue -teamproject $project.name -queueid $queue.id
    }
}