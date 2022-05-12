# Retrieves Web Hooks and Service Connections per Team Project

$coll = "http://tfsserver:8080/tfs/defaultcollection"
$apiurl = "$coll/_apis"
$HooksCsvPath = "C:\temp\hooks.csv"
$SvcConnectionsCsvPath = "C:\temp\svconn.csv"

Class ServiceConnection {
    [string]$TeamProject
    [string]$Name
    [string]$Type
    [string]$Url
}

$serviceconnections = New-Object System.Collections.ArrayList

# Web Hooks (not per Team Project)
$uri = "$apiurl/hooks/subscriptions"
$response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -UseDefaultCredentials
$subscriptions = ($response.Content | ConvertFrom-Json).value

$subs = $subscriptions | Select-Object -Property url, status, eventType, eventDescription, consumerId, consumerActionId
$subs | Export-Csv -Path $HooksCsvPath -UseCulture

# Get Team Projects
$uri = "$apiurl/projects?`$top=2000"
$response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -UseDefaultCredentials
$projects = ($response.Content | ConvertFrom-Json).value

# For each team project, get service connections, add them to a list and export to CSV
foreach ($project in $projects) {
    Write-Host "Checking Team Project '$($project.name)'"
    $uri = "$coll/$($project.name)/_apis/serviceendpoint/endpoints"
    $response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -UseDefaultCredentials
    $svcconns = ($response.Content | ConvertFrom-Json).value
    foreach ($svcconn in $svcconns) {
        $serviceconnection = New-Object ServiceConnection
        $serviceconnection.TeamProject = $project.name
        $serviceconnection.Name = $svcconn.name
        $serviceconnection.Type = $svcconn.type
        $serviceconnection.Url = $svcconn.url
        $serviceconnections.Add($serviceconnection)
    }
}

$serviceconnections | Export-Csv -Path $SvcConnectionsCsvPath -UseCulture
