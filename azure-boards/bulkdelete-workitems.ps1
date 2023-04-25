# Will bulk delete work items in batches of about 200 items (the limit in Azure DevOps)
# Also works on-prem (Azure DevOps Server), at least from version 2020 on
# Replace "MYPROJECT" and "MYAREAPATH" with your own

$org = "https://devopsserver/tfs/DefaultCollection"
$pat = Get-Content -Path ".\pat.txt"
$headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$AzureDevOpsProject = "MYPROJECT"
$AreaPath = "MYAREAPATH"

$body = @"
{
    "query": "Select [System.Id] From WorkItems Where [System.TeamProject] = '$($AzureDevOpsProject)' and [System.AreaPath] = '$($AzureDevOpsProject)\\$($AreaPath)'"
}
"@

$responseitems = Invoke-RestMethod '$org/_apis/wit/wiql?api-version=6.0' -Method 'POST' -Headers $headers -ContentType "application/json" -Body $body

$body = ""
$counter = 0
foreach ($witems in $responseitems.workItems)
{
    if ($counter -eq 0) {
        $body = "["
    }
    $body += @"
{
    "method": "DELETE",
    "uri": "/_apis/wit/workItems/$($witems.Id)?api-version=4.0-preview",
    "headers": {
        "Content-Type": "application/json-patch+json"
    }
},
"@
    $counter++
    if ($counter -ge 199) {
        $body = $body.TrimEnd(",")
        $body += "]"
        Invoke-RestMethod '$org/_apis/wit/$batch' -Method 'POST' -Headers $headers -ContentType "application/json" -Body $body
        $counter = 0
    }
}

$body = $body.TrimEnd(",")
$body += "]"
Invoke-RestMethod '$org/_apis/wit/$batch' -Method 'POST' -Headers $headers -ContentType "application/json" -Body $body
