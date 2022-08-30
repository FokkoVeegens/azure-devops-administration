# This script sets access levels for a list of users
# The list should be a .csv file with 2 columns; username and accesslevel
# I chose to make the csv file tab-separated, but you can change the $delimiter variable
# Accesslevel can be: stakeholder, basic, basicplustestplans, vspro, vsent

$ErrorActionPreference = "Stop"

$protocol = "https://"
$org = "dev.azure.com/YOURORG"
$pat = Get-Content -Path ".\pat.txt"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$inputfile = ".\input\useraccesslevels.csv"
$delimiter = "`t"

# **** Visual Studio Enterprise Subscription
# "accessLevel": {
#     "licensingSource": "msdn",
#     "accountLicenseType": "none",
#     "msdnLicenseType": "enterprise",
#     "licenseDisplayName": "Visual Studio Enterprise subscription",
#     "status": "active",
#     "statusMessage": "",
#     "assignmentSource": "unknown"
#     }

# **** Basic User
# "accessLevel": {
#     "licensingSource": "account",
#     "accountLicenseType": "express",
#     "msdnLicenseType": "none",
#     "licenseDisplayName": "Basic",
#     "status": "active",
#     "statusMessage": "",
#     "assignmentSource": "unknown"
#     }

# **** Basic + Test Plans
# "accessLevel": {
#     "licensingSource": "account",
#     "accountLicenseType": "advanced",
#     "msdnLicenseType": "none",
#     "licenseDisplayName": "Basic + Test Plans",
#     "status": "active",
#     "statusMessage": "",
#     "assignmentSource": "unknown"
#     }

# **** Stakeholder User
# "accessLevel": {
#     "licensingSource": "account",
#     "accountLicenseType": "stakeholder",
#     "msdnLicenseType": "none",
#     "licenseDisplayName": "Stakeholder",
#     "status": "pending",
#     "statusMessage": "",
#     "assignmentSource": "unknown"
#     }

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

function Invoke-RestPatch ($uri, $body, [bool]$usevalueproperty = $true)
{
    $output = (Invoke-WebRequest -Uri $uri -Method PATCH -ContentType "application/json-patch+json" -Body $body -Headers $header ) | ConvertFrom-Json
    if ($usevalueproperty)
    {
        return $output.value
    }
    else 
    {
        return $output
    }
}

function Get-UserEntitlementId ($username, $allusers)
{
    $userdetails = $allusers | Where-Object { $_.principalName -eq $user.username }
    if ($userdetails)
    {
        $entitlement = Get-JsonOutput -uri "$($protocol)vsaex.$($org)/_apis/userentitlements/$($userdetails.descriptor)" -usevalueproperty $false
        return $entitlement.id
    }
    else 
    {
        return $null
    }
}

function Update-AccessLevel($allusers, $username, [ValidateSet("basic","basicplustestplans","stakeholder","vspro","vsent")]$accesslevel)
{
    $entitlementId = Get-UserEntitlementId -username $username -allusers $allusers
    if (!($entitlementId))
    {
        Write-Host "User $username was not found in the list of known users" -ForegroundColor Yellow
        return $false
    }
    $accountLicenseType = ""
    $msdnLicenseType = ""
    $licensingSource = ""
    Switch ($accesslevel)
    {
        "basic" { $licensingSource = "account"; $accountLicenseType = "express"; $msdnLicenseType = "none" }
        "basicplustestplans" { $licensingSource = "account"; $accountLicenseType = "advanced"; $msdnLicenseType = "none" }
        "stakeholder" { $licensingSource = "account"; $accountLicenseType = "stakeholder"; $msdnLicenseType = "none" }
        "vspro" { $licensingSource = "msdn"; $accountLicenseType = "none"; $msdnLicenseType = "professional" }
        "vsent" { $licensingSource = "msdn"; $accountLicenseType = "none"; $msdnLicenseType = "enterprise" }
    }
    $body = @"
[
    {
        'from': '',
        'op': 'replace',
        'path': '/accessLevel',
        'value': {
            'accountLicenseType': '$accountLicenseType',
            'licensingSource': '$licensingSource',
            'msdnLicenseType': '$msdnLicenseType'
        }
    }
]
"@
    $result = Invoke-RestPatch -uri "$($protocol)vsaex.$($org)/_apis/userentitlements/$($entitlementId)?api-version=7.1-preview.3" -body $body -usevalueproperty $false
    if ($result.isSuccess -ne $true)
    {
        Write-Host "Update failed: $($result.results[0].errors[0].key) - $($result.results[0].errors[0].value)" -ForegroundColor Red
        return $false
    }
    else 
    {
        return $true
    }
}

function Get-AllUsers()
{
    return Get-JsonOutput -uri "$($protocol)vssps.$($org)/_apis/graph/users" 
}

$allusers = Get-AllUsers
$userstoupdate = Import-Csv -Path $inputfile -Delimiter $delimiter
foreach ($user in $userstoupdate)
{
    Write-Host "Updating $($user.username)"
    $updateresult = Update-AccessLevel -allusers $allusers -userid $user.username -accesslevel $user.accesslevel
    if ($updateresult)
    {
        Write-Host "User $($user.username) was updated successfully to access level '$($user.accesslevel)'" -ForegroundColor Green
    }
    else 
    {
        Write-Host "User $($user.username) update failed" -ForegroundColor Red
    }
}
