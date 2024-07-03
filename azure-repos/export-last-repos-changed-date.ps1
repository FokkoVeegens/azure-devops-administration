# This script will export a CSV file with the last change per Azure DevOps git repo and branch
# It will verify this for one Team Project

$Organization = "https://dev.azure.com/YOURORG"
$TeamProjectName = "YOURPROJECT"
$TargetFile = "C:\temp\repochangeddates.csv"
$CsvSeparator = ","
$PersonalAccessToken = "YOURPAT"

$ErrorActionPreference = 'Stop'

function Get-Headers($personalAccessToken = "") {
    if ($personalAccessToken) {
        $encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$personalAccessToken"))
        return @{Authorization = "Basic $encodedPat"}
    }
    else {
        return @{Authorization = "Bearer $env:SYSTEM_ACCESSTOKEN"}
    }
}

function Invoke-AzDoCall($path, [ValidateSet("Get", "Post", "Patch", "Put", "Delete")] [string]$method = "Get", $teamProjectName = "", $body = "", $resultProperty = "value", $useSingularApi = $false, $ContentType = "application/json", [switch]$returnStatusCode) {
    $api = "_apis"
    if ($useSingularApi) {
        $api = "_api"
    }

    $uri = "$Global_OrgUrl/$api/$path"
    if ($teamProjectName) {
        $uri = "$Global_OrgUrl/$teamProjectName/$api/$path"
    }
    
    if ($Global_LogApiUrls) {
        Write-Host "Call $method to: $uri" -ForegroundColor DarkGray
    }
    if ($Global_LogBody -and -not ([string]::IsNullOrEmpty($body))) {
        Write-Host "Body: $body" -ForegroundColor DarkGray
    }
    $result = $null
    if ($method -ne "Get" -and $method -ne "Delete") {
        $currentResult = Invoke-RestMethod -Uri $uri -Method $method -ContentType $ContentType -Headers $Global_Headers -Body $body -StatusCodeVariable "statusCode"
        if ($resultProperty) {
            $result = $currentResult."$resultProperty"
        }
        else {
            $result = $currentResult
        }
    }
    else {
        # ContinuationToken response header occurs when the result count exceeds Azure DevOps limits. 
        # While the ContinuationToken exists in the response header, we need to re-execute the request with the continuationtoken in the querystring
        $continuationToken = "init"
        while ($continuationToken) {
            $uriWithToken = $uri
            if ($continuationToken -ne "init") {
                if (([uri]$uriWithToken).Query) {
                    $uriWithToken += "&continuationtoken=$($continuationToken)"
                }
                else {
                    $uriWithToken += "?continuationtoken=$($continuationToken)"
                }
            }
            $currentResult = Invoke-RestMethod -Uri $uriWithToken -Method $method -ContentType $ContentType -Headers $Global_Headers -StatusCodeVariable "statusCode" -ResponseHeadersVariable "responseHeaders"
            if ($resultProperty) {
                $result += $currentResult."$resultProperty"
            }
            else {
                $result += $currentResult
            }
            $continuationToken = $responseHeaders."x-ms-continuationtoken"
        }
    }
    if($returnStatusCode){
        return $statusCode
    }
    else {
        return $result
    }
}

function Find-TeamProject($teamProjectName, [ValidateSet("Source","Target")][string]$Environment) {
    $teamProjects = Invoke-AzDoCall -path "projects" -Environment $Environment
    return ($teamProjects | Where-Object { $_.name -eq $teamProjectName })
}

function Get-Repos($teamProject) {
    return Invoke-AzDoCall -path "git/repositories" -teamProjectName $teamProject.name
}

function Test-Stats($teamProject, $repo) {
    $baseStats = Invoke-AzDoCall -path "git/repositories/$($repo.id)/stats" -teamProjectName $teamProject.name -resultProperty ""
    return ($baseStats.branchesCount -gt 0)
}

function Get-Stats($teamProject, $repo) {
    if (Test-Stats -teamProject $teamProject -repo $repo) {
        return Invoke-AzDoCall -path "git/repositories/$($repo.id)/stats/branches" -teamProjectName $teamProject.name
    }
    else {
        return $null
    }
}

$Global_Headers = Get-Headers -personalAccessToken $PersonalAccessToken
$Global_OrgUrl = $Organization
$Global_LogApiUrls = $false

$output = ""
$TeamProject = Find-TeamProject -teamProjectName $TeamProjectName
$repos = Get-Repos -teamProject $TeamProject
foreach ($repo in $repos) {
    if ($repo.isDisabled) {
        Write-Host "Repo '$($repo.name)' is disabled; skipping"
        continue
    }
    $stats = Get-Stats -teamProject $TeamProject -repo $repo
    foreach ($stat in $stats) {
        $output += "$($repo.name)$CsvSeparator$($stat.name)$CsvSeparator$($stat.commit.committer.date.ToString("yyyy-MM-dd HH:mm:ss"))`n"
    }
}
$output | Set-Content -Path $TargetFile -Encoding utf8
