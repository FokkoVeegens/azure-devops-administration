# Will export all Agent Pools to a json file, which can be used later on to import into another location

$coll = "http://tfsserver:8080/tfs/DefaultCollection"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$outputfile = "C:\temp\agentpools.json"

function Get-JsonOutput($uri)
{
    return (invoke-webrequest -Uri $uri -Method GET -ContentType "application/json" -Headers $header).Content
}

function Get-AgentPools()
{
    Get-JsonOutput -uri "$coll/_apis/distributedtask/pools" -usevalueproperty $true
}

Get-AgentPools | Set-Content -Path $outputfile
