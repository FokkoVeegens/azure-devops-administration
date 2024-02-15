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
 
function Get-WorkItemTypeStates($processTypeId, $witReferenceName) {
    return Invoke-AzDoCall -path "work/processes/$processTypeId/workItemTypes/$witReferenceName/states"
}

function Get-States($process, $workItemType) {
    $states = @()
    $witStates = Get-WorkItemTypeStates -processTypeId $process.typeId -witReferenceName $workItemType.referenceName
    if ($witStates | Where-Object { $_.customizationType -notin @("system", "inherited") }) {
        # Add name and stateCategory properties to the result, where the customizationType is not system
        foreach ($state in $witStates) {
            if ($state.customizationType -ne "system") {
                $states += [pscustomobject]@{
                    Process = $process.name
                    WorkItemType = $workItemType.name
                    WorkItemTypeCustom = $workItemType.customization
                    State = $state.name
                    StateCategory = $state.stateCategory
                }
            }
        }
    }
    return $states
}

function Get-Rules($process, $workItemType) {
    $rules = @()
    $witRules += Get-WorkItemRules -processTypeId $process.typeId -witReferenceName $workItemType.referenceName
    if ($witRules | Where-Object { $_.customizationType -ne "system" }) {
        foreach ($rule in $witRules) {
            if ($rule.customizationType -ne "system") {
                $rules += [pscustomobject]@{
                    Process = $process.name
                    WorkItemType = $workItemType.name
                    WorkItemTypeCustom = $workItemType.customization
                    Name = $rule.name
                    ConditionsCount = $rule.conditions.Count
                    ActionsCount = $rule.actions.Count
                    Enabled = (!$rule.isDisabled)
                }
            }
        }
    }
    return $rules
}

function Get-Fields($process, $workItemType) {
    $results = @()
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
    return $results
}

function Get-WorkItemRules($processTypeId, $witReferenceName) {
    return Invoke-AzDoCall -path "work/processes/$processTypeId/workItemTypes/$witReferenceName/rules"
}
 
$Global_Headers = Get-Headers -personalAccessToken $PersonalAccessToken
$Global_OrgUrl = Get-OrganizationUrl -organization $Organization
$Global_LogApiUrls = $false
 
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
$fieldsResults = @()
$statesResults = @()
$rulesResults = @()
foreach ($process in $usedProcesses) {
    Write-Host "Processing $($process.name)" -ForegroundColor Green
    $workItemTypes = Get-WorkItemTypesByProcess -processTypeId $process.typeId
    foreach ($workItemType in $workItemTypes) {
        Write-Host "  Processing $($workItemType.name)" -ForegroundColor DarkGray
        $statesResults += Get-States -process $process -workItemType $workItemType
        $rulesResults += Get-Rules -process $process -workItemType $workItemType
        $fieldsResults += Get-Fields -process $process -workItemType $workItemType
    }
}
$fieldsResults | Export-Csv -Path "$PSScriptRoot\fields.csv" -UseCulture -Encoding UTF8
$statesResults | Export-Csv -Path "$PSScriptRoot\states.csv" -UseCulture -Encoding UTF8
$rulesResults | Export-Csv -Path "$PSScriptRoot\rules.csv" -UseCulture -Encoding UTF8
