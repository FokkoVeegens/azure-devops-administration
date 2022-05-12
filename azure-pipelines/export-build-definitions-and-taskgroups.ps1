# Will export all Azure DevOps build definitions and task groups within a Team Project to json files in $filesPath

$AzureDevOpsPAT = "enteryourownPAT"
$AzureDevOpsAuthenicationHeader = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($AzureDevOpsPAT)")) }
$filesPath = "D:\output"
$baseUrl = "https://dev.azure.com/enteryourownorg/enteryourownteamproject/_apis"

function Write-BuildDefinition($id)
{
    $uri = "$baseUrl/build/definitions/$id`?api-version=6.1-preview.7"
    $output = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $AzureDevOpsAuthenicationHeader
    $filename = Join-Path -Path $filesPath -ChildPath "Build_$id.json"
    Set-Content -Path $filename -Value $output.Content
}

function Write-TaskgroupDefinition($id)
{
    $uri = "$baseUrl/distributedtask/taskgroups/$id`?api-version=6.0-preview.1"
    $output = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $AzureDevOpsAuthenicationHeader
    $filename = Join-Path -Path $filesPath -ChildPath "Taskgroup_$id.json"
    Set-Content -Path $filename -Value $output.Content
}

$uri = "$baseUrl/build/definitions?api-version=6.1-preview.7"
$response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $AzureDevOpsAuthenicationHeader
$builddefs = $response.Content | ConvertFrom-Json

foreach ($builddef in $builddefs.value)
{
    Write-BuildDefinition -id $builddef.id
}

$uri = "$baseUrl/distributedtask/taskgroups?api-version=6.0-preview.1"
$response = invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $AzureDevOpsAuthenicationHeader
$taskgroups = $response.Content | ConvertFrom-Json

foreach ($taskgroup in $taskgroups.value)
{
    Write-TaskgroupDefinition -id $taskgroup.id
}
