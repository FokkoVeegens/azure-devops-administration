# The Azure DevOps Data Import service to migrate from on-prem Azure DevOps Server to Azure DevOps Services doesn't support migrating Service Hooks
# This script can do exactly that. Currently it is required to have the on-prem server running, but it's very easy to extract the output to a .json file
# It cannot cope with passwords stored in the Service Hooks, so these need to be migrated manually
# NOTE: THIS SCRIPT WILL REMOVE EXISTING SERVICE HOOKS IN THE TARGET ORGANIZATION!!

$onpremcoll = "https://tfsserver:8080/tfs/DefaultCollection"
$cloudprotocol = "https://"
$cloudorg = "dev.azure.com/YOURORG"
$onprempat = Get-Content -Path ".\pat-onprem.txt"
$cloudpat = Get-Content -Path ".\pat-cloud.txt"
$onpremheader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($onprempat)")) }
$cloudheader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($cloudpat)")) }

function Get-JsonOutput($uri, $header, [bool]$usevalueproperty)
{
    $output = (invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $header) | ConvertFrom-Json
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Invoke-RestPost ($uri, $header, $body, [bool]$usevalueproperty = $true)
{
    $output = (Invoke-WebRequest -Uri $uri -Method POST -ContentType "application/json" -Body $body -Headers $header ) | ConvertFrom-Json
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Invoke-RestDelete ($uri, $header)
{
    Invoke-WebRequest -Uri $uri -Method DELETE -ContentType "application/json" -Headers $header | Out-Null
}

function New-CloudServiceHook ($publisherId, $eventType, $resourceVersion, $consumerId, $consumerActionId, $consumerInputs, $publisherInputs, $status)
{
    $urlprefix = ""
    if ($eventType -eq "ms.vss-release.deployment-completed-event" -or $eventType -eq "ms.vss-release.release-created-event")
    {
        # fix publisherId in case of Release Management related events
        $publisherId = "rm"
        $urlprefix = "vsrm."
    }

    if (!$resourceVersion)
    {
        $resourceVersion = "null"
    }
    else 
    {
        $resourceVersion = "'$resourceVersion'"
    }

    $body = @"
{
    'publisherId': '$publisherId',
    'eventType': '$eventType',
    'resourceVersion': $resourceVersion,
    'consumerId': '$consumerId',
    'consumerActionId': '$consumerActionId',
    'status': '$status',
    'publisherInputs': $publisherInputs,
    'consumerInputs': $consumerInputs
    }
"@
    Invoke-RestPost -uri "$($cloudprotocol)$($urlprefix)$($cloudorg)/_apis/hooks/subscriptions?api-version=7.1-preview.1" -header $cloudheader -body $body | Out-Null
}

function Get-ProjectsOnPrem ()
{
    return Get-JsonOutput -uri "$onpremcoll/_apis/projects" -header $onpremheader -usevalueproperty $true
}

function Remove-CloudServiceHook ($subscriptionId)
{
    Invoke-RestDelete -uri "$($cloudprotocol)$($cloudorg)/_apis/hooks/subscriptions/$($subscriptionId)?api-version=7.1-preview.1" -header $cloudheader
}

function Get-ServiceHooksOnPrem ()
{
    return Get-JsonOutput -uri "$onpremcoll/_apis/hooks/subscriptions" -header $onpremheader -usevalueproperty $true
}

function Get-ServiceHooksCloud()
{
    return Get-JsonOutput -uri "$($cloudprotocol)$($cloudorg)/_apis/hooks/subscriptions" -header $cloudheader -usevalueproperty $true
}

# Clean subscriptions
$cloudservicehooks = Get-ServiceHooksCloud
foreach ($cloudservicehook in $cloudservicehooks)
{
    Remove-CloudServiceHook -subscriptionId $cloudservicehook.id
}

# Transfer subscriptions
$onpremservicehooks = Get-ServiceHooksOnPrem
$projectsonprem = Get-ProjectsOnPrem
foreach ($onpremservicehook in $onpremservicehooks)
{
    $projectofsubs = $projectsonprem | Where-Object { $_.id -eq $onpremservicehook.publisherInputs.projectId }
    Write-Host "Processing project '$($projectofsubs.name)', publisher '$($onpremservicehook.publisherId)', eventType '$($onpremservicehook.eventType)', id '$($onpremservicehook.id)'"
    if ($onpremservicehook.consumerInputs.basicAuthPassword)
    {
        Write-Host "This subscription cannot be migrated because it contains a basic auth password for user '$($onpremservicehook.consumerInputs.basicAuthUsername)'" -ForegroundColor Red
        continue
    }
    if ($onpremservicehook.consumerId -eq "teams")
    {
        Write-Host "Microsoft Teams Service Hooks are managed by Microsoft Teams. It needs to be recreated from the Microsoft Teams application. The action is '$($onpremservicehook.consumerActionId)'. This Service Hook will not be migrated." -ForegroundColor Yellow
        continue
    }
    try {
        New-CloudServiceHook -publisherId $onpremservicehook.publisherId `
        -eventType $onpremservicehook.eventType `
        -resourceVersion $onpremservicehook.resourceVersion `
        -consumerId $onpremservicehook.consumerId `
        -consumerActionId $onpremservicehook.consumerActionId `
        -consumerInputs (($onpremservicehook.consumerInputs | ConvertTo-Json) -replace "`"", "'") `
        -publisherInputs (($onpremservicehook.publisherInputs | ConvertTo-Json) -replace "`"", "'") `
        -status $onpremservicehook.status        
        Write-Host "Service Hook succeeded" -ForegroundColor Green
    }
    catch {
        $errormsg = ($_.ErrorDetails.Message | ConvertFrom-Json).message
        Write-Host "Service Hook failed; $errormsg" -ForegroundColor Red
    }
}