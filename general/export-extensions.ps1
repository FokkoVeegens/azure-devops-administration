# This script exports Azure DevOps Marketplace extensions and contributions within the extensions for analysis purposes
# Don't forget to enter your own Personal Access Token (pat) and Azure DevOps Organization (org)

$pat = "UseYourOwn"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$org = "dev.azure.com/yourorg"
$protocol = "https://"
$outputpath = "C:\temp\out.csv"

Class ExtensionContribution {
    [string]$ExtensionId
    [string]$PublisherId
    [string]$Version
    [string]$ContributionType
    [string]$ContributionName
}

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

function Get-Extensions()
{
    return Get-JsonOutput -uri "$($protocol)extmgmt.$($org)/_apis/extensionmanagement/installedextensions" -usevalueproperty $true
}

$extensions = Get-Extensions | Where-Object { $_.publisherId -ne "ms" }
$outputextensions = New-Object System.Collections.ArrayList
foreach ($extension in $extensions) {
    foreach ($contribution in $extension.contributions) {
        $outputextension = New-Object ExtensionContribution
        $outputextension.ExtensionId = $extension.extensionId
        $outputextension.PublisherId = $extension.publisherId
        $outputextension.Version = $extension.version
        $outputextension.ContributionType = $contribution.type
        $outputextension.ContributionName = $contribution.properties.name
        $outputextensions.Add($outputextension)
    }
}

$outputextensions | Export-Csv -Path $outputpath -UseCulture
