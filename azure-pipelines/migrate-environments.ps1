# This script will migrate Azure DevOps environments including approvals and checks from one Team Project to another within the same Azure DevOps organization
# The "$TargetTeamName" will automatically be prefixed with the word "Team "

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

function Get-Environments($teamProject) {
    return Invoke-AzDoCall -path "pipelines/environments" -teamProjectName $teamProject.name
}

function Get-NewEnvironmentName($environmentName, $teamName) {
    return "$($teamName)-$($environmentName)"
}

function Add-Environment($teamProject, $environment, $teamName) {
    $body = @{
        name = (Get-NewEnvironmentName -environmentName $environment.name -teamName $teamName)
        description = $environment.description
    } | ConvertTo-Json -EscapeHandling EscapeNonAscii
    return Invoke-AzDoCall -path "pipelines/environments?api-version=7.2-preview.1" -body $body -method Post -teamProjectName $teamProject.name -resultProperty ""
}

function Get-Checks($teamProject, $environment) {
    return Invoke-AzDoCall -path "pipelines/checks/configurations?resourcetype=environment&resourceId=$($environment.id)&`$expand=settings" -teamProjectName $teamProject.name
}

function Remove-Checks($teamProject, $environment) {
    $checks = Get-Checks -teamProject $teamProject -environment $environment
    foreach ($check in $checks) {
        Invoke-AzDoCall -path "pipelines/checks/configurations/$($check.id)?api-version=7.2-preview.1" -method Delete -teamProjectName $teamProject.name
    }
}

function New-Check($check, $environment, $teamProject) {
    $body = ""
    switch ($check.type.name) {
        "ExclusiveLock" {
            $body = @{
                timeout = $check.timeout
                resource = @{
                    type = "environment"
                    id = $environment.id
                }
                type = @{
                    id = $check.type.id
                    name = $check.type.name
                }
                
            } | ConvertTo-Json -EscapeHandling EscapeNonAscii -Depth 5
        }
        "Approval" {
            $body = @{
                timeout = $check.timeout
                resource = @{
                    type = "environment"
                    id = $environment.id
                }
                type = @{
                    id = $check.type.id
                    name = $check.type.name
                }
                settings = @{
                    requesterCannotBeApprover = $check.settings.requesterCannotBeApprover
                    approvers = $check.settings.approvers
                    executionOrder = $check.settings.executionOrder
                    minRequiredApprovers = $check.settings.minRequiredApprovers
                    instructions = $check.settings.instructions
                    blockedApprovers = $check.settings.blockedApprovers
                }
            } | ConvertTo-Json -EscapeHandling EscapeNonAscii -Depth 5
        }
        "Task Check" {
            $body = @{
                timeout = $check.timeout
                resource = @{
                    type = "environment"
                    id = $environment.id
                }
                type = @{
                    id = $check.type.id
                    name = $check.type.name
                }
                settings = @{
                    displayName = $check.settings.displayName
                    definitionRef = @{
                        id = $check.settings.definitionRef.id
                        name = $check.settings.definitionRef.name
                        version = $check.settings.definitionRef.version
                    }
                    inputs = @{
                        allowedBranches = $check.settings.inputs.allowedBranches
                        ensureProtectionOfBranch = $check.settings.inputs.ensureProtectionOfBranch
                    }
                    retryInterval = $check.settings.retryInterval
                }
            } | ConvertTo-Json -EscapeHandling EscapeNonAscii -Depth 5
        }
        Default {
            Write-Host "Unknown check type: $checkType" -ForegroundColor Red
            return
        }
    }
    if ($body) {
        Invoke-AzDoCall -path "pipelines/checks/configurations?api-version=7.2-preview.1" -method Post -teamProjectName $teamProject.name -body $body
    }
}

$Global_Headers = Get-Headers -personalAccessToken (Get-Content -Path "$PSScriptRoot\..\pat.txt")
$Global_OrgUrl = Get-OrganizationUrl -organization $OrganizationName
$Global_LogApiUrls = $true

$sourceTeamProject = Find-TeamProject -teamProjectName $SourceTeamProjectName
$targetTeamProject = Find-TeamProject -teamProjectName $TargetTeamProjectName

$sourceEnvironments = Get-Environments -teamProject $sourceTeamProject
$targetEnvironments = Get-Environments -teamProject $targetTeamProject

if ($targetEnvironments.GetType() -ne [System.Array]) {
    $targetEnvironments = @($targetEnvironments)
}

foreach ($sourceEnvironment in $sourceEnvironments) {
    $targetEnvironment = $targetEnvironments | Where-Object { $_.name -eq (Get-NewEnvironmentName -environmentName $sourceEnvironment.name -teamName $TargetTeamName) }
    if (!$targetEnvironment) {
        $targetEnvironment = Add-Environment -teamProject $targetTeamProject -environment $sourceEnvironment -teamName $TargetTeamName
        Write-Host "Added environment: $($targetEnvironment.name)"
    }
    else {
        Remove-Checks -teamProject $targetTeamProject -environment $targetEnvironment
        Write-Host "Environment $($sourceEnvironment.name) already exists"
    }

    # Checks
    $checks = Get-Checks -teamProject $sourceTeamProject -environment $sourceEnvironment
    foreach ($check in $checks) {
        Write-Host "Adding check $($check.type.name) to environment $($targetEnvironment.name)"
        New-Check -check $check -environment $targetEnvironment -teamProject $targetTeamProject
    }
}
