# Checks if the 1-click-child-links extension (https://marketplace.visualstudio.com/items?itemName=ruifig.vsts-work-item-one-click-child-links)
# is actually used in Azure DevOps

$ErrorActionPreference = "Stop"
$AzDoPat = Get-Content -Path "$PSScriptRoot\pat.txt"
$AzDoOrg = "https://dev.azure.com/YOURDEVOPSORG"

$AzDoHeaders = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($AzDoPat)")) }

function Invoke-AzDoCall($path, [ValidateSet("Get", "Post", "Patch", "Put")] [string]$method = "Get", $teamProject = "", $team = "", $body = "", $resultProperty = "value", $useSingularApi = $false) {
    $api = "_apis"
    if ($useSingularApi) {
        $api = "_api"
    }
    $uri = "$AzDoOrg/$api/$path"
    if ($teamProject) {
        if ($team) {
            $uri = "$AzDoOrg/$teamProject/$team/$api/$path"
        }
        else {
            $uri = "$AzDoOrg/$teamProject/$api/$path"
        }
        
    }
    if ($LogApiUrls) {
        Write-Host "Call naar: $uri" -ForegroundColor DarkGray
    }
    $result = $null
    try {
        if ($method -ne "Get") {
            if ($method -eq "Patch") {
                $result = Invoke-RestMethod -Uri $uri -Method $method -ContentType "application/json-patch+json" -Headers $AzDoHeaders -Body $body
            }
            else {
                $result = Invoke-RestMethod -Uri $uri -Method $method -ContentType "application/json" -Headers $AzDoHeaders -Body $body
            }   
        }
        else {
            $result = Invoke-RestMethod -Uri $uri -Method $method -ContentType "application/json" -Headers $AzDoHeaders
        } 
    }
    catch {
        Write-Error $_
        exit 1
    }

    if ($resultProperty) {
        return $result."$resultProperty"
    }
    else {
        return $result
    }
}

function Get-Projects () {
    return Invoke-AzDoCall -path "projects"
}

function Get-Teams ($teamProject) {
    return Invoke-AzDoCall -path "projects/$($teamProject.id)/teams"
}

$teamProjects = Get-Projects
foreach ($teamProject in $teamProjects) {
    Write-Host "Processing '$($teamProject.name)'"
    $teams = Get-Teams -teamProject $teamProject
    foreach ($team in $teams) {
        $templates = Invoke-AzDoCall -path "wit/templates" -teamProject $teamProject.name -team $team.name -resultProperty ""
        if ($templates.count -gt 0) {
            foreach ($template in $templates.value) {
                if ($template.description -match "[\[\{]") {
                    Write-Host "Found config in '$($teamProject.name) - $($team.name)'"
                }
            }
        }
    }
}
