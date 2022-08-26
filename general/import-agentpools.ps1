# This script will recreate agent pools exported from another TFS/Azure DevOps
# Use export-agentpools.ps1 first to create the agentpools.json file
# Will set the autoUpdate and autoProvision properties, but not the maintenance settings!

$ErrorActionPreference = "Stop"

$org = "https://dev.azure.com/YOURORG"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$inputfile = ".\input\agentpools.json"

function Get-JsonOutput($uri, [bool]$usevalueproperty)
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

function New-AgentPool ($name, $autoProvision = $true, $autoUpdate = $true)
{
    $ap = "false"
    if ($autoProvision)
    {
        $ap = "true"
    }
    $au = "false"
    if ($autoUpdate)
    {
        $au = "true"
    }
    $body = "{ 'name': '$name', 'autoProvision': $ap, 'autoUpdate': $au }"
    return Invoke-RestPost -uri "$org/_apis/distributedtask/pools?api-version=7.1-preview.1" -body $body -usevalueproperty $false
}

function Get-AgentPools()
{
    Get-JsonOutput -uri "$org/_apis/distributedtask/pools" -usevalueproperty $true
}

$poolsintarget = Get-AgentPools
$poolsinfile = (Get-Content -Path $inputfile | ConvertFrom-Json).value | Sort-Object -Property id
foreach ($pool in $poolsinfile)
{
    $existingpool = $poolsintarget | Where-Object { $_.name -eq $pool.name }
    if ($existingpool)
    {
        Write-Host "Pool '$($pool.name)' already exists with id: $($existingpool.id) (original id: $($pool.id))"
        continue
    }
    $newpool = New-AgentPool -name $pool.name -autoProvision $pool.autoProvision -autoUpdate $pool.autoUpdate
    Write-Host "Creating pool '$($pool.name)' with id $($newpool.id) (original id: $($pool.id))"
}
