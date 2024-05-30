# Will migrate iterations from one project to the other
# Will currently only work with 1 level of iterations

param (
    $OrganizationName,
    $SourceTeamProjectName,
    $TargetTeamProjectName,
    $TargetTeamName
)

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

function Get-OrganizationUrl($organization) {
    return "https://dev.azure.com/$organization"
}

function Get-OrganizationUrlWithPrefix($prefix) {
    return $Global_OrgUrl -replace "https://", "https://$prefix."
}

function Invoke-AzDoCall($path, [ValidateSet("Get", "Post", "Patch", "Put", "Delete")] [string]$method = "Get", $teamProjectName = "", $body = "", $resultProperty = "value", $useSingularApi = $false, $urlPrefix = "", $ContentType = "application/json", [switch]$returnStatusCode) {
    $api = "_apis"
    if ($useSingularApi) {
        $api = "_api"
    }
    $currentOrgUrl = $Global_OrgUrl
    if ($urlPrefix) {
        $currentOrgUrl = Get-OrganizationUrlWithPrefix -prefix $urlPrefix
    }

    $uri = "$currentOrgUrl/$api/$path"
    if ($teamProjectName) {
        $uri = "$currentOrgUrl/$teamProjectName/$api/$path"
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

function Find-TeamProject($teamProjectName) {
    $teamProjects = Invoke-AzDoCall -path "projects"
    return ($teamProjects | Where-Object { $_.name -eq $teamProjectName })
}

function Get-Iterations($teamProject) {
    return Invoke-AzDoCall -path "wit/classificationnodes/iterations?`$depth=1" -teamProjectName $teamProject.name -resultProperty "children"
}

function Add-Iteration($teamProject, $iteration, $teamName) {
    $body = @{
        name = $iteration.name
        attributes = @{
            startDate = $iteration.attributes.startDate
            finishDate = $iteration.attributes.finishDate
        }
    } | ConvertTo-Json -EscapeHandling EscapeNonAscii -Depth 2
    $null = Invoke-AzDoCall -path "wit/classificationnodes/iterations/Team $($teamName)?api-version=7.2-preview.2" -method Post -teamProjectName $teamProject.name -body $body
}

$Global_Headers = Get-Headers -personalAccessToken (Get-Content -Path "$PSScriptRoot\pat.txt")
$Global_OrgUrl = Get-OrganizationUrl -organization $OrganizationName
$Global_LogApiUrls = $true

$sourceTeamProject = Find-TeamProject -teamProjectName $SourceTeamProjectName
$targetTeamProject = Find-TeamProject -teamProjectName $TargetTeamProjectName

$iterations = Get-Iterations -teamProject $sourceTeamProject
foreach ($iteration in $iterations) {
    Add-Iteration -teamProject $targetTeamProject -iteration $iteration -teamName $TargetTeamName
}
