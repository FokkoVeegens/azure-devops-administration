# Exports all Git repos in all Team Projects along with byte sizes to a CSV file

$ErrorActionPreference = "Stop"

$org = "YOURORG" # Azure DevOps Organization (exclude https://dev.azure.com/)
$outputfilepath = "C:\temp\repos.csv" # Path to the CSV file containing the output

$Collection = "https://dev.azure.com/$org"
$pat = Get-Content -Path ".\pat.txt"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}

Class RepoResult
{
    [string]$Id
    [string]$TeamProject
    [string]$Name
    [int]$ByteSize
    [bool]$IsDisabled
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

function Get-GitRepos($teamProject) {
    return Invoke-AzDoCall -path "git/repositories" -teamProject $teamProject.name
}

function Get-GitRepo($teamProject, $repoId) {
    return Invoke-AzDoCall -path "git/repositories/$($repoId)" -teamProject $teamProject.name -resultProperty ""
}

$RepoResults = New-Object System.Collections.ArrayList
$TeamProjects = Get-Projects
foreach ($TeamProject in $TeamProjects) {
    $Gitrepos = Get-GitRepos -teamProject $TeamProject
    foreach ($Gitrepo in $Gitrepos) {
        $GitRepoDetails = Get-GitRepo -teamProject $TeamProject -repoId $GitRepo.id
        $RepoResult = New-Object RepoResult
        $RepoResult.Id = $GitRepoDetails.id
        $RepoResult.TeamProject = $TeamProject.name
        $RepoResult.Name = $GitRepoDetails.name
        $RepoResult.ByteSize = $GitRepoDetails.size
        $RepoResult.IsDisabled = $GitRepoDetails.isDisabled
        $null = $RepoResults.Add($RepoResult)
    }
}

$RepoResults | Export-Csv -Path $outputfilepath -UseCulture -Encoding utf8