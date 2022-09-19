# First export-deploymentgroup-agents.ps1 needs to be run

$ErrorActionPreference = "Stop"

$pat = Get-Content -Path ".\pat.txt"
$org = "https://dev.azure.com/YOURORG"
$agents = Import-Csv -Path "C:\Temp\deploymentgroup_agents.csv" -UseCulture

$registerscript = {
    param (
        $installpath,
        $pat,
        $deploymentGroupName,
        $org,
        $teamproject
    )
    If (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole( [Security.Principal.WindowsBuiltInRole] "Administrator"))
    {
        throw "Run command in an administrator PowerShell prompt"
    }
    If ($PSVersionTable.PSVersion -lt (New-Object System.Version("3.0")))
    {
        throw "The minimum version of Windows PowerShell that is required by the script (3.0) does not match the currently running version of Windows PowerShell." 
    }
    Set-Location -Path $installpath
    .\config.cmd remove `
        --unattended `
        --auth "pat" `
        --token $pat
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
    .\config.cmd --deploymentgroup `
        --deploymentgroupname $deploymentGroupName `
        --agent $env:COMPUTERNAME `
        --runasservice `
        --work '_work' `
        --url $org `
        --projectname $teamproject `
        --auth PAT `
        --token $pat
}

foreach ($agent in $agents)
{
    Write-Host "Processing agent '$($agent.AgentName)' in Team Project '$($agent.TeamProject)' in Pool '$($agent.PoolName)'"
    if ($agent.AgentEnabled -eq $false -or $agent.AgentStatus -ne "online")
    {
        Write-Host "Skip agent because it used to be offline/disabled"
        continue
    }
    $ErrorActionPreference = 'Continue'
    Invoke-Command -ComputerName $agent.AgentComputerName `
        -ScriptBlock $registerscript `
        -ArgumentList $agent.AgentHomeDirectory, $pat, $agent.PoolName, $org, $agent.TeamProject
    $ErrorActionPreference = 'Stop'
}
