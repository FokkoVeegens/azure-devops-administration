# This script will export all custom fields in inheritance process templates. It will write the projects + their process template to the output (semicolon separated)
# You'll need to set your own Azure DevOps Organization name and you need to have a pat.txt in place in the same directory as this script, containing your Personal Access Token
# Also, you need to define the projects for which you want to run this script in the $projects variable
# Apologies for not the most beautiful and performing code, but hey, it works...

$ErrorActionPreference = 'Stop'

$Organization = "YOURORG"
$projects = @("TeamProject1", "TeamProject2")
$PersonalAccessToken = Get-Content -Path "$PSScriptPath\pat.txt"

function Get-Headers($personalAccessToken) {
    if ($null -ne $personalAccessToken) {
        $encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$personalAccessToken"))
        return @{Authorization = "Basic $encodedPat"}
    } else {
        $azureDevOpsResourceId = "499b84ac-1321-427f-aa17-267ca6975798"
        $accessToken = az account get-access-token --resource $azureDevOpsResourceId --query "accessToken" --output tsv
        return @{Authorization = "Bearer $accessToken"}
    }
}

function Get-OrganizationUrl($organization) {
    return "https://dev.azure.com/$organization"
}

function Get-OrganizationUrlWithPrefix($prefix) {
    return $Global_OrgUrl -replace "https://", "https://$prefix."
}

function Invoke-AzDoCall($path, [ValidateSet("Get", "Post", "Patch", "Put", "Delete")] [string]$method = "Get", $teamProjectName = "", $body = "", $resultProperty = "value", $useSingularApi = $false, $urlPrefix = "", $ContentType = "application/json") {
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
        $currentResult = Invoke-RestMethod -Uri $uri -Method $method -ContentType $ContentType -Headers $Global_Headers -Body $body
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
            $currentResult = Invoke-RestMethod -Uri $uriWithToken -Method $method -ContentType $ContentType -Headers $Global_Headers
            if ($resultProperty) {
                $result += $currentResult."$resultProperty"
            }
            else {
                $result += $currentResult
            }
            $continuationToken = $responseHeaders."x-ms-continuationtoken"
        }
    }

    return $result
}

function Get-TeamProjects() {
    return Invoke-AzDoCall -path "projects"
}

function Get-TemplatesWithProjects() {
    return Invoke-AzDoCall -path "work/processes?`$expand=projects"
}

function Get-WorkItemTypesByProcess($processTypeId) {
    return Invoke-AzDoCall -path "work/processes/$processTypeId/workitemtypes"
}

function Get-WorkItemTypeFields($processTypeId, $witReferenceName) {
    return Invoke-AzDoCall -path "work/processes/$processTypeId/workitemtypes/$witReferenceName/fields"
}

$Global_Headers = Get-Headers -personalAccessToken $PersonalAccessToken
$Global_OrgUrl = Get-OrganizationUrl -organization $Organization
$Global_LogApiUrls = $true

$processes = Get-TemplatesWithProjects


$usedProcesses = @()
foreach ($process in $processes) {
    foreach ($project in $process.projects) {
        if ($projects | Where-Object { $_ -eq $project.name }) {
            Write-Host "$($project.name);$($process.name)"
            $usedProcesses += $process
        }
    }
}

$usedProcesses = $usedProcesses | Sort-Object -Property "name" | Select-Object -Unique -Property "name", "typeId"
$results = @()
foreach ($process in $usedProcesses) {
    $workItemTypes = Get-WorkItemTypesByProcess -processTypeId $process.typeId
    foreach ($workItemType in $workItemTypes) {
        $fields = Get-WorkItemTypeFields -processTypeId $process.typeId -witReferenceName $workItemType.referenceName
        foreach ($field in $fields) {
            if ($field.customization -ne "custom") {
                continue
            }
            $result = [pscustomobject]@{
                Process = $process.name
                WorkItemType = $workItemType.name
                WorkItemTypeCustom = $workItemType.customization
                Field = $field.name
                FieldCustom = $field.customization
                FieldType = $field.type
                FieldRequired = $field.required
            }
            $results += $result
        }
    }
}
$results | Export-Csv -Path "$PSScriptRoot\process.csv" -UseCulture -Encoding UTF8
