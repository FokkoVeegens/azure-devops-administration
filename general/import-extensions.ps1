# This script will use the output of the export-extensions.ps1 script as input
# Using these two scripts it's possible to copy the installed extensions from on-prem to the cloud when performing an Azure DevOps Data Import
# Don't forget to configure the variables below. Make sure you use the PAT for your CLOUD Azure DevOps Services and not the on-prem Azure DevOps Server

$ErrorActionPreference = "Stop"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$org = "dev.azure.com/YOURORG"
$protocol = "https://"
$inputpath = "C:\temp\out.csv"

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

$extensions = Import-Csv -Path $inputpath
$extensions = $extensions | Select-Object PublisherId,ExtensionId | Sort-Object -Property PublisherId,ExtensionId -Unique
foreach ($extension in $extensions)
{
    try {
        Invoke-RestPost -uri "$($protocol)extmgmt.$($org)/_apis/extensionmanagement/installedextensionsbyname/$($extension.PublisherId)/$($extension.ExtensionId)?api-version=7.1-preview.1" -body "" -usevalueproperty $false
        Write-Host "Extension '$($extension.PublisherId).$($extension.ExtensionId)' installed" -ForegroundColor Green
    }
    catch {
        $errormsg = ($_.ErrorDetails.Message | ConvertFrom-Json).message
        Write-Host "Extension '$($extension.PublisherId).$($extension.ExtensionId)' skipped; $errormsg" -ForegroundColor Yellow
    }    
}