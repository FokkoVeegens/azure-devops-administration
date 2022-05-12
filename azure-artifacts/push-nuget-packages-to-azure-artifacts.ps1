# Uploads a directory of *.nupkg files to an Azure DevOps Server (onprem)
# Please use the latest version of nuget.exe (https://www.nuget.org/downloads)

$source = "URL TO YOUR AZURE ARTIFACTS FEED" # Should end with /nuget/v3/index.json
$pathtonugetexe = "PATH TO YOUR NUGET.EXE"
$pathtopackages = "PATH TO YOUR NUGET PACKAGES DIRECTORY"

Set-Alias -Name nuget -Value $pathtonugetexe
$packages = Get-ChildItem -Path $pathtopackages -Filter *.nupkg
foreach ($package in $packages)
{
    Write-Host "Pushing $package"
    nuget push $package.FullName -Source $source -ApiKey "Azure DevOps Services"
    if ($LASTEXITCODE -eq 0)
    {
        Remove-Item -Path $package.FullName -Force
    }
    else
    {
        Write-Host "$package failed"
    }
}
