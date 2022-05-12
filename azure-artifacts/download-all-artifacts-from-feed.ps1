# This script will download all versions of all packages in an Azure DevOps Azure Artifacts feed. Useful if e.g. you need to know the size of the feed.

$nugetpath = "D:\NuGet\nuget.exe"
Set-Alias -Name nuget -Value $nugetpath
$outputpath = "D:\DownloadedPackages"
$nugetsource = "NameOfTheNugetSource" # register a source first using "nuget sources add"
$feedbaseurl = "https://[MyAzureDevOpsServerUrl]/tfs/DefaultCollection/_apis/packaging/feeds/[feedguid]/nuget/packages/" # Feed guid can be obtained by downloading a package from an Azure Artifacts feed and finding the download URL

$packages = (nuget list -Source $nugetsource -AllVersions)
foreach ($package in $packages)
{
    $packagename = ($package -split " ")[0]
    $packageversion = ($package -split " ")[1]
    Invoke-WebRequest -Uri "$($feedbaseurl)$($packagename)/versions/$($packageversion)/content" -OutFile "$($outputpath)\$($packagename).$($packageversion).nupkg" -UseDefaultCredentials
}
