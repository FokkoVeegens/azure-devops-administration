# Will remove all Git Repositories from a Team Project

$Global_Org = "https://dev.azure.com/YOURORG"
$Global_TeamProjectName = "YOURTEAMPROJECT"

$RepositoriesToExclude = @("repo1", "repo2")

$PersonalAccessToken = Get-Content -Path "$PSScriptRoot\pat.txt"
$Global_Headers = @{Authorization = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$PersonalAccessToken")))" }
$ErrorActionPreference = 'Stop'

function Get-Repos($teamproject) {
    $repos = (Invoke-RestMethod -Uri "$Global_Org/$teamproject/_apis/git/repositories" -Method Get -Headers $Global_Headers).value
    return $repos
}

function Remove-Repo($repo) {
    $null = Invoke-RestMethod -Uri "$Global_Org/_apis/git/repositories/$($repo.id)?api-version=7.0" -Method Delete -Headers $Global_Headers
}

$repos = Get-Repos -teamproject $Global_TeamProjectName
foreach ($repo in $repos) {
    if ($RepositoriesToExclude -contains $repo.name) {
        continue
    }
    Write-Host "Deleting repo $($repo.name)" -ForegroundColor Yellow
    Remove-Repo -teamproject $Global_TeamProjectName -repo $repo
}
