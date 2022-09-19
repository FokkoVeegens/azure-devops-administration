# In this script I will provide functions to fix validation errors occurring during a validation of a Team Project Collection
# by the migrator.exe that is part of the DataMigrationTool
# The Repairables csv file should be a file containing 2 columns; GroupSid and ScopeId
# More information can be found here: https://learn.microsoft.com/en-us/azure/devops/migrate/migration-troubleshooting?view=azure-devops#isverror-100014

$ErrorActionPreference = "Stop"
$TFSSecurityExePath = "C:\Program Files\Azure DevOps Server 2020\Tools\TFSSecurity.exe"
$coll = "https://tfs.anywhere365.net/tfs/Anywhere365%20UCC"
$repairablespath = "C:\Temp\input.csv"

if (!(Get-Alias -Name tfssecurity -ErrorAction SilentlyContinue))
{
    New-Alias -Name tfssecurity -Value $TFSSecurityExePath
}

function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

function Repair-Error100014($GroupSid, $ScopeId)
{
    tfssecurity /a+ Identity "$ScopeId\\" Read "sid:$GroupSid" ALLOW /collection:$coll
}

$repairables = Import-Csv -Delimiter "," -Path $repairablespath
foreach ($repairable in $repairables)
{
    Repair-Error100014 -GroupSid $repairable.GroupSid -ScopeId $repairable.ScopeId
}
