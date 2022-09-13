$protocol = "https://"
$org = "dev.azure.com/YOURORG"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$inputpath = "C:\temp\servicehooks"

function Get-JsonOutput($uri, [bool]$usevalueproperty = $true)
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

function Invoke-RestPost ($uri, $body, [bool]$usevalueproperty = $true)
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

function Invoke-RestDelete ($uri)
{
    Invoke-WebRequest -Uri $uri -Method DELETE -ContentType "application/json" -Headers $header | Out-Null
}

function New-ServiceHook ($publisherId, $eventType, $resourceVersion, $consumerId, $consumerActionId, $consumerInputs, $publisherInputs, $status)
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
    Invoke-RestPost -uri "$($protocol)$($urlprefix)$($org)/_apis/hooks/subscriptions?api-version=7.1-preview.1" -body $body | Out-Null
}

function Get-TeamProjects ()
{
    return Get-JsonOutput -uri "$org/_apis/projects"
}

function Remove-ServiceHook ($subscriptionId)
{
    Invoke-RestDelete -uri "$($protocol)$($org)/_apis/hooks/subscriptions/$($subscriptionId)?api-version=7.1-preview.1"
}

function Get-ServiceHooks()
{
    return Get-JsonOutput -uri "$($protocol)$($org)/_apis/hooks/subscriptions" -usevalueproperty $true
}

# Clean subscriptions
$servicehooks = Get-ServiceHooks
foreach ($servicehook in $servicehooks)
{
    Remove-ServiceHook -subscriptionId $servicehook.id
}

# Transfer subscriptions
$inputfiles = Get-ChildItem -Path $inputpath -Filter *.json
$teamprojects = Get-TeamProjects
foreach ($inputfile in $inputfiles)
{
    Write-Host "Processing file '$($inputfile)'"
    if ($inputfile.FullName.EndsWith("_done.json"))
    {
        Write-Host "Skipping file because it is already done"
        continue
    }
    $onpremservicehook = $inputfile.FullName | Get-Content | ConvertFrom-Json -Depth 100
    $projectofsubs = $teamprojects | Where-Object { $_.id -eq $onpremservicehook.publisherInputs.projectId }
    Write-Host "Processing project $($projectofsubs.name), publisher $($onpremservicehook.publisherId), eventType $($onpremservicehook.eventType), id $($onpremservicehook.id)"
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
        New-ServiceHook -publisherId $onpremservicehook.publisherId `
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
    Rename-Item -Path $inputfile.FullName -NewName ($inputfile.FullName -replace ".json", "_done.json")
}
