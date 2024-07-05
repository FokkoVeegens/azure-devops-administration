# Will disable all Git Repositories in a Team Project

$Global_Org = "https://dev.azure.com/YOURORG"
$Global_TeamProjectName = "YOURTEAMPROJECT"

$PersonalAccessToken = Get-Content -Path "$PSScriptRoot\pat.txt"
$Global_Headers = @{Authorization = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$PersonalAccessToken")))" }
$ErrorActionPreference = 'Stop'

function Get-Repos($teamprojectname) {
    $repos = (Invoke-RestMethod -Uri "$Global_Org/$teamprojectname/_apis/git/repositories" -Method Get -Headers $Global_Headers).value
    return $repos
}

function Disable-Repo($teamprojectname, $repo) {
    $body = @"
{
    "isDisabled": true
}
"@
    $null = Invoke-RestMethod -Uri "$Global_Org/$teamprojectname/_apis/git/repositories/$($repo.id)?api-version=7.0" -Method Patch -Headers $Global_Headers -Body $body -ContentType "application/json"
}

$repos = Get-Repos -teamprojectname $Global_TeamProjectName
foreach ($repo in $repos) {
    Write-Host "Disabling repo $($repo.name)" -ForegroundColor Yellow
    if ($repo.isDisabled) {
        Write-Host "Repo $($repo.name) is already disabled" -ForegroundColor Green
        continue
    }
    Disable-Repo -teamprojectname $Global_TeamProjectName -repo $repo
}
