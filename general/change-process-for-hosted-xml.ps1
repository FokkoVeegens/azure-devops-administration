# This script is not finished yet. It can be used to replace words in an Azure DevOps Hosted XML Process Template
# It will download the template and extract the zip, then replace some string. I used it for a 7Pace Timetracker migration
# The upload of the process template still needs to be implemented. The rest of the script works as designed.

$ErrorActionPreference = "Stop"

$org = "https://dev.azure.com/YOURORG"
$pat = Get-Content -Path ".\pat.txt"
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$header = @{Authorization = "Basic $encodedPat"}
$temppath = "C:\Temp"
$extractedpath = "$temppath\extracted"

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

function Get-DownloadFile ($uri, $destination)
{
    Invoke-WebRequest -Uri $uri -OutFile $destination -UseBasicParsing:$false -ContentType "application/zip" -Headers $header
}

function Get-ProcessesList()
{
    return Get-JsonOutput -uri "$org/_apis/process/processes"
}

function Get-ProcessFiles ($id, $name)
{
    $filepath = "$temppath\$name.zip"
    if (Test-Path -Path $filepath)
    {
        Remove-Item -Path $filepath -Force
    }
    Get-DownloadFile -uri "$org/_apis/work/processAdmin/processes/export/$id" -destination $filepath

    $processextractedpath = "$extractedpath\$name"
    if (Test-Path -Path $processextractedpath)
    {
        Remove-Item -Path $processextractedpath -Recurse -Force
    }
    New-Item -Path $processextractedpath -ItemType Directory
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($filepath, $processextractedpath)
}

function Update-Witds($path)
{
    $witds = Get-ChildItem -Path $path -Filter *.xml
    foreach ($witd in $witds)
    {
        $witname = $witd.name -replace ".xml", ""
        Write-Host "Processing '$witname'"
        $xml = Get-Content -Path $witd.fullname
        if ($xml -contains "TimetrackerOnPremises")
        {
            $xml = $xml -replace "TimetrackerOnPremises", "Timetracker"
            Set-Content -Value $xml -Path $witd.fullname -Encoding UTF8 -Force
        }
        else 
        {
            Write-Host "No 'TimetrackerOnPremises' found"
        }
    }
}

$processes = Get-ProcessesList
foreach ($process in $processes)
{
    if ($process.type -ne "custom")
    {
        Write-Host "Skipping inheritance template '$($process.name)'"
        continue
    }
    Write-Host "Processing template '$($process.name)'"
    Get-ProcessFiles -id $process.id -name $process.name
    Update-Witds -path "$extractedpath\$($process.name)\WorkItem Tracking\TypeDefinitions"
    # Request URL: https://dev.azure.com/YOURORG/_apis/work/processAdmin/processes/Import?replaceExistingTemplate=true
    # POST
}
