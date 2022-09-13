# Will export servicehooks to .json files as part of an Azure DevOps Data Import
# The Data Import does not (correctly) import service hooks

$coll = "http://tfsserver:8080/tfs/DefaultCollection"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$outputpath = "C:\temp\servicehooks"

function Get-JsonOutput($uri, [bool]$usevalueproperty = $true)
{
    $output = (invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $header) | ConvertFrom-Json -Depth 100
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Get-ServiceHooks ()
{
    return Get-JsonOutput -uri "$coll/_apis/hooks/subscriptions"
}

$servicehooks = Get-ServiceHooks
if (!(Test-Path -Path $outputpath))
{
    New-Item -Path $outputpath -ItemType Directory
}
foreach ($servicehook in $servicehooks)
{
    $servicehook | ConvertTo-Json -Depth 100 | Out-File -FilePath "$($outputpath)\$($servicehook.id).json"
}
