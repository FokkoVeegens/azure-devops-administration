# This script will re-register all agents in the right pools and with the right user-defined capabilities, as part of the Azure DevOps Data Import
# It is required to first run the script export-agent-pools-and-agents.ps1 on the on-prem server to generate the input files
# Then the column "AgentPassword" needs to be filled for agents that do not use the NETWORK SERVICE account

$ErrorActionPreference = "Stop"

$pat = Get-Content -Path ".\pat.txt"
$org = "https://dev.azure.com/anywhere365dev"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}
$logsdir = "C:\temp\agentinstalllogs"

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

    # Verify internet connection on server
    $result = (Get-CimInstance -ClassName Win32_PingStatus -Filter "Address='www.google.nl' AND Timeout=1000") | ConvertTo-Json -depth 100 | ConvertFrom-Json
    if (!$result.IPV4Address -and !$result.IPV6Address)
    {
        Write-Host "Server has no internet connection, skipping agent reconfiguration"
        return
    }
    Set-Location -Path $agentpath
    $ErrorActionPreference = "SilentlyContinue"
    .\config.cmd remove --unattended --auth "pat" --token $pat
    if (Test-Path -Path ".\.agent")
    {
        Remove-Item -Path ".\.agent" -Force
    }
    if (Test-Path -Path ".\.credentials")
    {
        Remove-Item -Path ".\.credentials" -Force
    }
    if (Test-Path -Path ".\.credentials_rsaparams")
    {
        Remove-Item -Path ".\.credentials_rsaparams" -Force
    }
    $ErrorActionPreference = "Stop"
    if ($username -and $pass)
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
    $output = (Invoke-WebRequest -Uri $uri -Method PATCH -ContentType "application/json" -Body $body -Headers $header ) | ConvertFrom-Json
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
    $result = Invoke-Command -ComputerName $machinename -ScriptBlock $registerscript -ArgumentList $poolname, $agentname, $agentpath, $org, $pat, $username, $pass
    $result | Add-Content -Path "$logsdir\$($poolname)_$($agentname).txt"
}

function Add-UserCapabilities ($oldagentid, $newagentid, $poolid)
{
    $agentcapabilities = $usercapabilities | Where-Object { $_.AgentId -eq $oldagentid }
    $body = "{`n"
    foreach ($agentcapability in $agentcapabilities)
    {
        $body += "'$($agentcapability.UserCapabilityKey -replace "\\", "\\")': '$($agentcapability.UserCapabilityValue -replace "\\", "\\")',`n"
    }
    $body = $body.Substring(0, $body.Length - 2)
    $body += "`n}"
    Invoke-RestPut -uri "$org/_apis/distributedtask/pools/$poolid/agents/$newagentid/usercapabilities?api-version=5.0-preview.1" -body $body
}

function Update-AgentState ($poolid, $agentid, [bool]$enabled)
{
    $body = "{ 'id': $agentid, 'enabled': $enabled }".ToLower()
    Invoke-RestPatch -uri "$org/_apis/distributedtask/pools/$poolid/agents/$($agentid)?api-version=5.0-preview.1" -body $body
}

function Get-AgentPools ()
{
    return Get-JsonOutput -uri "$org/_apis/distributedtask/pools"
}

function Get-AgentByName ($agentname, $poolid)
{
    return Get-JsonOutput -uri "$org/_apis/distributedtask/pools/$poolid/agents?agentName=$agentname"
}

if (!(Test-Path -Path $logsdir))
{
    New-Item -Path $logsdir -ItemType Directory
}
$agentpools = Get-AgentPools
foreach ($agent in $agentsandpools)
{
    Write-Host "Processing agent '$($agent.AgentName)' in pool '$($agent.AgentPoolName)'"
    if ($agent.AgentOS -ne "Windows_NT")
    {
        Write-Host "Skipping agent '$($agent.AgentName)', because it is a non-Windows agent"
        continue
    }
    if ($agent.AgentStatus -eq "offline")
    {
        Write-Host "Skipping agent '$($agent.AgentName)', because it was offline in the old situation"
        continue
    }
    $ErrorActionPreference = "Break"
    if ($agent.AgentUserName.EndsWith("$"))
    {
        # Uses NETWORK SERVICE account
        Write-Host "Registering agent using the NETWORK SERVICE account"
        Install-Agent -machinename $agent.AgentComputerName `
            -poolname $agent.AgentPoolName `
            -agentname $agent.AgentName `
            -agentpath $agent.AgentHomeDirectory
    }
    else
    {
        if ($agent.AgentPassword)
        {
            Write-Host "Registering agent using the $($agent.AgentUsername) account"
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
            Write-Host "Agent $($agent.AgentName) cannot be reconfigured because no password is supplied, skipping agent"
            continue
        }
    }
    $ErrorActionPreference = "Stop"

    Write-Host "Retrieving new poolid and agentid"
    $agentpoolid = ($agentpools | Where-Object { $_.name -eq $agent.AgentPoolName }).id
    $newagent = Get-AgentByName -agentname $agent.AgentName -poolid $agentpoolid
    if (!$newagent)
    {
        # Agent was not registered, probably because of lack of an internet connection. Continue with next
        continue
    }
    $agentid = $newagent.id
    if ($agent.AgentHasUserCapabilities -eq "True")
    {
        Write-Host "Setting capabilities"
        Add-UserCapabilities -oldagentid $agent.AgentId -newagentid $agentid -poolid $agentpoolid
    }
    if ($agent.AgentEnabled -eq "False")
    {
        Write-Host "Disabling agent to replicate original situation"
        Update-AgentState -agentid $agentid -enabled $false -poolid $agentpoolid
    }
    Write-Host "Agent '$($agent.AgentName)': agentid old/new $($agent.AgentId)/$agentid poolid old/new $($agent.AgentPoolId)/$agentpoolid"
}
Write-Host "Finished importing agents"
