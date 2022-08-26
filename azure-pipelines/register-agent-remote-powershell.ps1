# This script will use remote PowerShell to install a new Azure Pipelines agent on a machine
# You'll need to download the installation file first, this is not (yet) part of the script
# It will use C:\Temp on the destination server to copy the installation file to
# Refer to the following documentation to find all "unattended" options for the agent installation:
# https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-windows?view=azure-devops

$ErrorActionPreference = "Stop"

$pat = Get-Content -Path ".\pat.txt"
$org = "https://dev.azure.com/YOURORG"
$agentfilename = "vsts-agent-win-x64-2.206.1.zip"
$pathtoagentzip = "D:\Scripts\$agentfilename"

$script = {
    param (
        $machinename,
        $poolname,
        $agentname,
        $destinationpath,
        $agentfilename,
        $org,
        $pat
    )

    $agentpath = "$destinationpath\$agentname"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    New-Item -Path $agentpath -ItemType Directory -Force
    Set-Location -Path $agentpath
    [System.IO.Compression.ZipFile]::ExtractToDirectory("C:\Temp\$agentfilename", "$PWD")
    .\config.cmd --unattended --url $org --auth "pat" --token $pat --pool $poolname --agent $agentname --runAsService
    Remove-Item -Path "C:\Temp\$agentfilename" -Force
}

function Install-Agent ($machinename, $poolname, $agentname, $destinationpath)
{
    if (!(Test-Path "\\$machinename\C`$\Temp"))
    {
        New-Item -Path "\\$machinename\C`$\Temp" -ItemType Directory -Force
    }
    Copy-Item -Path $pathtoagentzip -Destination "\\$machinename\C`$\Temp\$agentfilename" -Force

    Invoke-Command -ComputerName $machinename -ScriptBlock $script -ArgumentList $machinename, $poolname, $agentname, $destinationpath, $agentfilename, $org, $pat
}

# Example
Install-Agent -machinename "BuildServer01" -poolname "Default" -agentname "BuildServer01-Agent01" -destinationpath "C:\agents"
