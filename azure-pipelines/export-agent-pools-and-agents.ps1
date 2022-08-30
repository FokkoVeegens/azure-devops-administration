$ErrorActionPreference = "Stop"

$coll = "https://dev.azure.com/YOURORG"
$filepathagentsandpools = "C:\temp\agentsandpools.csv"
$filepathusercapabilities = "C:\temp\usercapabilities.csv"
$pat = Get-Content -Path ".\pat.txt"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}
$apiurl = "$coll/_apis"
 
Class AgentPoolEntry {
    [int]$AgentPoolId
    [string]$AgentPoolName
    [int]$AgentId
    [string]$AgentName
    [bool]$AgentEnabled
    [string]$AgentStatus
    [string]$AgentVersion
    [string]$AgentHomeDirectory
    [string]$AgentUserDomain
    [string]$AgentUserName
    [string]$AgentComputerName
    [string]$AgentOS
    [bool]$AgentHasUserCapabilities
}

Class UserCapability {
    [int]$AgentId
    [string]$UserCapabilityKey
    [string]$UserCapabilityValue
}

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

function Get-Pools ()
{
    return Get-JsonOutput -uri "$apiurl/distributedtask/pools"
}

function Get-Agents ($poolid)
{
    return Get-JsonOutput -uri "$apiurl/distributedtask/pools/$poolid/agents?includeCapabilities=true"
}

$agentpools = Get-Pools
 
$agentpoolentries = New-Object System.Collections.ArrayList
$usercapabilities = New-Object System.Collections.ArrayList
foreach ($agentpool in $agentpools)
{
    Write-Host "Processing pool '$($agentpool.name)'"
    if ($agentpool.isHosted)
    {
        Write-Host "Skipping pool, because it is Microsoft-hosted"
        continue
    }
    $agents = Get-Agents -poolid $agentpool.id
    foreach ($agent in $agents)
    {
        Write-Host "  Processing agent '$($agent.name)'"
        $agentpoolentry = New-Object AgentPoolEntry
        $agentpoolentry.AgentPoolId = $agentpool.id
        $agentpoolentry.AgentPoolName = $agentpool.name
        $agentpoolentry.AgentId = $agent.id
        $agentpoolentry.AgentName = $agent.name
        $agentpoolentry.AgentEnabled = $agent.enabled
        $agentpoolentry.AgentStatus = $agent.status
        $agentpoolentry.AgentVersion = $agent.version
        $agentpoolentry.AgentHomeDirectory = $agent.systemCapabilities.'Agent.HomeDirectory'
        $agentpoolentry.AgentUserDomain = $agent.systemCapabilities.USERDOMAIN
        $agentpoolentry.AgentUserName = $agent.systemCapabilities.USERNAME
        $agentpoolentry.AgentComputerName = $agent.systemCapabilities.COMPUTERNAME
        $agentpoolentry.AgentOS = $agent.systemCapabilities.'Agent.OS'
        $agentpoolentry.AgentHasUserCapabilities = ($null -ne $agent.userCapabilities)
        $agentpoolentries.Add($agentpoolentry) | Out-Null

        if ($agent.userCapabilities)
        {
            $members = $agent.userCapabilities | Get-Member -MemberType NoteProperty
            foreach ($member in $members)
            {
                $usercapentry = New-Object UserCapability
                $usercapentry.AgentId = $agent.id
                $usercapentry.UserCapabilityKey = $member.name
                $usercapentry.UserCapabilityValue = $agent.userCapabilities."$($member.name)"
                $usercapabilities.Add($usercapentry) | Out-Null
            }
        }
    }
}

Write-Host "Writing CSV file"
$agentpoolentries | Export-Csv -Path $filepathagentsandpools -UseCulture
$usercapabilities | Export-Csv -Path $filepathusercapabilities -UseCulture
Write-Host "Done"
