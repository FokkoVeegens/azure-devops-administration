# This script cleans up test runs older than n days
# It uses a Personal Access Token, which should be stored in a file called pat.txt in the same directory. The file should only contain this string
# It is advisable to run the following queries afterwards (if you're on an on-prem installation), to ensure the data is really gone: https://github.com/FokkoVeegens/azure-devops-server-useful-sql-scripts/blob/main/cleanup-prune-deleted-data.sql

$pat = Get-Content -Path ".\pat.txt"
$org = "https://dev.azure.com/myorg" # Ensure your organization or collection URL is here
$project = "MyProject" # Enter Team Project name to cleanup
$encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":$pat"))
$minimumCleanupAgeInDays = 175 # Test runs older than this amount of days will be removed

# Retrieve all test runs of the selected Team Project
$jsonResponse = (Invoke-WebRequest -Uri "$org/$project/_apis/test/runs?includeRunDetails=true&api-version=5.0" -Method "GET" -ContentType application/json -Headers @{Authorization = "Basic $encodedPat"}).Content | ConvertFrom-Json

# Parse JSON
$testruns = $jsonResponse.value

# Determine upper boundary of cleanup run (clean up test runs up to this date)
$minimumCleanupAgeDate = (Get-Date).AddDays(($minimumCleanupAgeInDays * -1))

# Get runs that match this date condition
$selectedruns = $testruns | Where-Object { $_.startedDate -lt $minimumCleanupAgeDate }

Write-Host "Deleting $($selectedruns.Count) testrun(s)"
$i = 0

# Delete runs
foreach ($testrun in $selectedruns)
{
    $i += 1
    $progress = $i / $selectedruns.Count * 100
    Write-Progress -Activity "Removing test runs" -Status "$([math]::Round($progress, 1))% Complete:" -PercentComplete $progress

    # Execute deletion
    $result = Invoke-WebRequest -Uri "$org/$project/_apis/test/runs/$($testrun.id)?api-version=5.0" -Method "DELETE" -Headers @{Authorization = "Basic $encodedPat"} | Select-Object -Expand StatusCode

    # HTTP status should be 204, else stop execution
    if ($result -ne 204)
    {
        Write-Host "Deleting testrun with id $($testrun.id) failed with status code $($result)"
        exit 1
    }
}
