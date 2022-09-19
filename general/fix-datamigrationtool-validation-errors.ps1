# In this script I will provide functions to fix validation errors occurring during a validation of a Team Project Collection
# by the migrator.exe that is part of the DataMigrationTool
# The Repairables csv file should be a file containing 2 columns; GroupSid and ScopeId
# More information can be found here: https://learn.microsoft.com/en-us/azure/devops/migrate/migration-troubleshooting?view=azure-devops#isverror-100014
# The Process Templates File Path contains xml files that have been exported (witd, categories etc) and are ready to import

$ErrorActionPreference = "Stop"
$TFSSecurityExePath = "C:\Program Files\Azure DevOps Server 2020\Tools\TFSSecurity.exe"
$WitAdminExePath = "C:\Program Files\Microsoft Visual Studio\2022\TeamExplorer\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\witadmin.exe"
$coll = "http://tfsserver:8080/tfs/DefaultCollection"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$processtemplatefilespath = "C:\Temp\ProcessTemplateFiles"
$repairablespath = "C:\Temp\input.csv"

Set-Alias -Name tfssecurity -Value $TFSSecurityExePath
Set-Alias -Name witadmin -Value $WitAdminExePath

function Import-Categories ($teamproject)
{
    Write-Host "Updating categories for Team Project '$teamproject'"
    witadmin importcategories /collection:$coll /p:$teamproject /f:"$processtemplatefilespath\$teamproject-categories.xml"
}

function Import-Witd ($teamproject, $witdname)
{
    Write-Host "Updating '$witdname' for Team Project '$teamproject'"
    witadmin importwitd /collection:$coll /p:$teamproject /f:"$processtemplatefilespath\$teamproject-$witdname.xml"
}

function Import-ProcessConfig ($teamproject)
{
    Write-Host "Updating processconfig for Team Project '$teamproject'"
    witadmin importprocessconfig /collection:$coll /p:$teamproject /f:"$processtemplatefilespath\$teamproject-processconfig.xml"
}

function Invoke-RestPatch ($uri, $body)
{
    Invoke-WebRequest -Uri $uri -Method PATCH -ContentType "application/json" -Body $body -Headers $header
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
