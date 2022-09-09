# This script will re-register all agents in the right pools and with the right user-defined capabilities, as part of the Azure DevOps Data Import
# It is required to first run the script export-agent-pools-and-agents.ps1 to generate the input files

# **********************************************
# This script has not been tested yet!!
# **********************************************

$ErrorActionPreference = "Stop"

$pat = Get-Content -Path ".\pat.txt"
$org = "https://dev.azure.com/YOURORG"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}

$agentsandpools = Import-Csv -Path "C:\Temp\agentsandpools.csv" -UseCulture
$usercapabilities = Import-Csv -Path "C:\Temp\usercapabilities.csv" -UseCulture
$agentpools = ""

$registerscript = {
    param (
        $poolname,
        $agentname,
        $agentpath,
        $org,
        $pat,
        $username,
        $pass
    )

    Set-Location -Path $agentpath
    .\config.cmd remove --unattended --auth "pat" --token $pat
    if ($username -and $password)
    {
        .\config.cmd --unattended `
            --url $org `
            --auth "pat" `
            --token $pat `
            --pool $poolname `
            --agent $agentname `
            --runAsService `
            --windowsLogonAccount $username `
            --windowsLogonPassword $pass
    }
    else 
    {
        .\config.cmd --unattended `
            --url $org `
            --auth "pat" `
            --token $pat `
            --pool $poolname `
            --agent $agentname `
            --runAsService
    }
    
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

function Invoke-RestPatch ($uri, $body, [bool]$usevalueproperty = $true)
{
    $output = (Invoke-WebRequest -Uri $uri -Method PATCH -ContentType "application/json-patch+json" -Body $body -Headers $header ) | ConvertFrom-Json
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Invoke-RestPut ($uri, $body, [bool]$usevalueproperty = $true)
{
    $output = (Invoke-WebRequest -Uri $uri -Method PUT -ContentType "application/json" -Body $body -Headers $header ) | ConvertFrom-Json
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Install-Agent ($machinename, $poolname, $agentname, $agentpath, $username, $pass)
{
    Invoke-Command -ComputerName $machinename -ScriptBlock $registerscript -ArgumentList $poolname, $agentname, $agentpath, $org, $pat
}

function Add-UserCapabilities ($agentid, $poolid)
{
    $agentcapabilities = $usercapabilities | Where-Object { $_.AgentId -eq $agentid }
    foreach ($agentcapability in $agentcapabilities)
    {
        $body = "{ '$($agentcapability.UserCapabilityKey)': '$($agentcapability.UserCapabilityValue)' }"
        Invoke-RestPut -uri "$org/_apis/distributedtask/pools/$poolid/agents/$agentid/usercapabilities" -body $body
    }
}

function Update-AgentState ($poolid, $agentid, [bool]$enabled)
{
    $body = "{ 'id': $agentid, 'enabled': $enabled }"
    Invoke-RestPatch -uri "$org/_apis/distributedtask/pools/$poolid/agents/$($agentid)?api-version=7.1-preview.1" -body $body
}

function Get-AgentPools ()
{
    return Get-JsonOutput -uri "$org/_apis/distributedtask/pools"
}

function Get-AgentByName ($agentname, $poolid)
{
    return Get-JsonOutput -uri "$org/_apis/distributedtask/pools/$poolid/agents?agentName=$agentname"
}

$agentpools = Get-AgentPools
foreach ($agent in $agentsandpools)
{
    if ($agent.AgentUserName.EndsWith("$"))
    {
        # Uses NETWORK SERVICE account
        Install-Agent -machinename $agent.AgentComputerName `
            -poolname $agent.AgentPoolName `
            -agentname $agent.AgentName `
            -agentpath $agent.AgentHomeDirectory
    }
    else
    {
        if ($agent.AgentPassword)
        {
            # Use specific credentials
            Install-Agent -machinename $agent.AgentComputerName `
                -poolname $agent.AgentPoolName `
                -agentname $agent.AgentName `
                -agentpath $agent.AgentHomeDirectory `
                -username "$($agent.AgentUserDomain)\$($agent.AgentUserName)" `
                -pass $agent.AgentPassword
        }
        else 
        {
            Write-Host "Agent $($agent.AgentName) cannot be reconfigured because no password is supplied"
        }
    }
    
    $agentpoolid = $agentpools | Where-Object { $_.name -eq $agent.AgentPoolName }
    $agentid = (Get-AgentByName -agentname $agent.AgentName -poolid $agentpoolid).id
    if ($agent.AgentHasUserCapabilities -eq "True")
    {
        Add-UserCapabilities -agentid $agentid -poolid $agentpoolid
    }
    if ($agent.AgentEnabled -eq "False" -or $agent.AgentStatus -eq "offline")
    {
        Update-AgentState -agentid $agentid -enabled $false -poolid $agentpoolid
    }
    Write-Host "Agent '$($agent.AgentName)': agentid old/new $($agent.AgentId)/$agentid poolid old/new $($agent.AgentPoolId)/$agentpoolid"
}
