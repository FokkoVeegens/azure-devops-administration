# Exports all Environments in all Team Projects

$ErrorActionPreference = "Stop"

$org = "delta-n-devops" # Azure DevOps Organization (exclude https://dev.azure.com/)
$outputfilepath = "C:\temp\environments.csv" # Path to the CSV file containing the output

$Collection = "https://dev.azure.com/$org"
$pat = Get-Content -Path ".\pat.txt"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}

Class Environment {
    [string]$TeamProject
    [int]$Id
    [string]$Name
    [string]$Description
    [string]$CreatedBy
    [datetime]$CreatedOn
    [string]$ChangedBy
    [datetime]$ChangedOn
    [string]$ResourceTypes
}

function Invoke-AzDoCall($path, [ValidateSet("Get", "Post", "Patch", "Put")] [string]$method = "Get", $teamProject = "", $body = "", $resultProperty = "value", $useSingularApi = $false) {
    $api = "_apis"
    if ($useSingularApi) {
        $api = "_api"
    }
    $uri = "$Collection/$api/$path"
    if ($teamProject) {
        $uri = "$Collection/$teamProject/$api/$path"
    }
    if ($LogApiUrls) {
        Write-Host "Call naar: $uri" -ForegroundColor DarkGray
    }
    $result = $null
    if ($method -ne "Get") {
        $result = Invoke-RestMethod -Uri $uri -Method $method -ContentType "application/json" -headers $header -Body $body
    }
    else {
        $result = Invoke-RestMethod -Uri $uri -Method $method -ContentType "application/json" -headers $header
    }
    if ($resultProperty) {
        return $result."$resultProperty"
    }
    else {
        return $result
    }
}


function Get-Projects() {
    return Invoke-AzDoCall -path "projects"
}

function Get-Environments($teamProject) {
    return Invoke-AzDoCall -path "distributedtask/environments" -teamProject $teamProject.name
}

function Get-Environment($teamProject, $environmentId) {
    return Invoke-AzDoCall -path "distributedtask/environments/$($environmentId)?expands=resourceReferences" -teamProject $teamProject.name -resultProperty ""
}

$results = New-Object System.Collections.ArrayList
$TeamProjects = Get-Projects
foreach ($TeamProject in $TeamProjects) {
    $Environments = Get-Environments -teamProject $TeamProject
    foreach ($Environment in $Environments) {
        $EnvironmentDetails = Get-Environment -teamProject $TeamProject -environmentId $Environment.id
        $ResourceTypes = $EnvironmentDetails.resources | Select-Object -Property type -Unique | Join-String -Separator ", " -Property type
        $result = New-Object Environment
        $result.TeamProject = $TeamProject.name
        $result.Id = $Environment.id
        $result.Name = $Environment.name
        $result.Description = $Environment.description
        $result.CreatedBy = $Environment.createdBy.displayName
        $result.CreatedOn = $Environment.createdOn
        $result.ChangedBy = $Environment.lastModifiedBy.displayName
        $result.ChangedOn = $Environment.lastModifiedOn
        $result.ResourceTypes = $ResourceTypes
        $null = $results.Add($result)
    }
}

$results | Export-Csv -Path $outputfilepath -UseCulture -Encoding utf8
