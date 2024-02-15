# This script will export the usage ratio of custom fields (based on inheritance process customization)
# You can provide a list of Team Projects for which the data needs to be retrieved

$ErrorActionPreference = 'Stop'

$Organization = "YOURORG"
$projects = @("Project 1", "Project 2")

$PersonalAccessToken = Get-Content -Path "$PSScriptRoot\pat.txt"

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

function Get-Fields() {
    return Invoke-AzDoCall -path "wit/fields"
}

function Get-TotalWorkItemCount($teamProjectName, $workItemType) {
    $body = @{
        query = "Select [System.Id] From WorkItems Where [System.TeamProject] = '$teamProjectName' and [System.WorkItemType] = '$workItemType' and [System.State] NOT IN ('Removed', 'Done', 'Closed')"
    } | ConvertTo-Json
    $results = $null
    try {
        $results = Invoke-AzDoCall -path "wit/wiql?`$top=20000&api-version=7.2-preview.2" -method Post -teamProjectName $teamProjectName -body $body -resultProperty "workItems"    
    }
    catch {
        if ($_ -match "VS402337") {
            Write-Host "$($teamProjectName) - $($workItemType) - Query exceeded the limit of 20.000 items, count not possible" -ForegroundColor Red
            return -1
        }
        else {
            Write-Host $_.Exception.InnerException.Message -ForegroundColor Red
            return -1
        }
    }
    return ($results | Measure-Object).Count
}

function Get-FilledFieldCount($teamProjectName, $fieldName, $workItemType, $fieldDefinitions) {
    $field = $fieldDefinitions | Where-Object { $_.name -eq $fieldName }
    if ($null -eq $field) {
        Write-Host "Field $fieldName not found" -ForegroundColor Red
        return 0
    }
    $fieldRefName = $field.referenceName
    $comparer = "<> ''"
    if ($field.type -eq "boolean") {
        $comparer = "= true"
    }
    elseif ($field.type -eq "html") {
        $comparer = "is not empty"
    }
    $body = @{
        query = "Select [System.Id] From WorkItems Where [System.TeamProject] = '$teamProjectName' and [System.WorkItemType] = '$($workItemType.name)' and [$fieldRefName] $comparer and [System.State] NOT IN ('Removed', 'Done', 'Closed')"
    } | ConvertTo-Json
    $results = Invoke-AzDoCall -path "wit/wiql?`$top=20000&api-version=7.2-preview.2" -method Post -teamProjectName $teamProjectName -body $body -resultProperty "workItems"
    return ($results | Measure-Object).Count
}

function Get-Project($teamProjectName) {
    $allProjects = Invoke-AzDoCall -path "projects"
    return $allProjects | Where-Object { $_.name -eq $teamProjectName }
}

function Get-ProcessTemplateOfProject($teamProject) {
    $projectProperties = Invoke-AzDoCall -path "projects/$($teamProject.id)/properties"
    $processTemplateId = ($projectProperties | Where-Object { $_.name -eq "System.ProcessTemplateType" }).value
    return Invoke-AzDoCall -path "work/processes/$processTemplateId" -resultProperty ""
}

function Get-WorkItemTypesByProcess($processTypeId) {
    return Invoke-AzDoCall -path "work/processes/$processTypeId/workitemtypes"
}
 
function Get-WorkItemTypeFields($processTypeId, $witReferenceName) {
    return Invoke-AzDoCall -path "work/processes/$processTypeId/workitemtypes/$witReferenceName/fields"
}

$Global_Headers = Get-Headers -personalAccessToken $PersonalAccessToken
$Global_OrgUrl = Get-OrganizationUrl -organization $Organization
$Global_LogApiUrls = $false

$fieldDefinitions = Get-Fields

$results = @()
foreach ($project in $projects) {
    Write-Host "Processing $project" -ForegroundColor Green
    $processTemplate = Get-ProcessTemplateOfProject -teamProject (Get-Project -teamProjectName $project)
    $workitemtypes = Get-WorkItemTypesByProcess -processTypeId $processTemplate.typeId
    foreach ($workItemType in $workitemtypes) {
        Write-Host "  Processing $($workItemType.name)" -ForegroundColor DarkGray
        $fields = Get-WorkItemTypeFields -processTypeId $processTemplate.typeId -witReferenceName $workItemType.referenceName | Where-Object { $_.customization -notin @("system", "inherited") }
        $total = Get-TotalWorkItemCount -teamProjectName $project -workItemType $workItemType.name
        foreach ($field in $fields) {
            $filled = Get-FilledFieldCount -teamProjectName $project -fieldName $field.name -workItemType $workItemType -fieldDefinitions $fieldDefinitions
            $results += [PSCustomObject]@{
                Project = $project
                ProcessTemplate = $processTemplate.name
                WorkItemType = $workItemType.name
                Field = $field.name
                FieldType = $field.type
                Filled = $filled
                Total = $total
            }
        }
    }
} 
$results | Export-Csv -Path "$PSScriptPath\field-usage.csv" -NoTypeInformation
