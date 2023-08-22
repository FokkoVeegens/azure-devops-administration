# Please check https://gist.github.com/Ba4bes/29afffc1a8708169e9f40b326b162ff3#file-invoke-azdorepomigration-ps1 for this
# Usage is described in this blog: https://4bes.nl/2021/07/25/migrate-azure-devops-repos-with-powershell/
# Pull requests cannot be migrated
# Below is a slightly altered version that can do cross Azure DevOps Organization migrations

# NOTE: THE DEFAULT PROJECT REPO IS NOT OVERWRITTEN, IF IN THE SOURCE THE REPO EXISTS AND IS FILLED, THEN THE TARGET WILL BE EMPTY
# THIS NEEDS TO BE FIXED

$ErrorActionPreference = 'Stop'
function Invoke-AzDoRepoMigration {
    <#
    .SYNOPSIS
    Migrates git repo(s) from one Azure DevOps project to another.
    .DESCRIPTION
    This function migrates git repo(s) from one Azure DevOps project to another.
    If a repo is already in the target project, it will be skipped.
    If no repo-parameter is given, all repos will be migrated.
    The source repo will not be deleted.
    .PARAMETER SourceUserName
    The Azure DevOps user name of the source Azure DevOps organization.
    .PARAMETER DestinationUserName
    The Azure DevOps user name of the destination Azure DevOps organization.
    .PARAMETER SourceToken
    The Azure DevOps PAT token in the source organization.
    Requires full permission to:
    - Code
    - Service Connections
    .PARAMETER DestinationToken
    The Azure DevOps PAT token in the destination organization.
    Requires full permission to:
    - Code
    - Service Connections
    .PARAMETER SourceOrganizationName
    The Azure DevOps organization name as it is visible in the URL, of the source organization.
    .PARAMETER DestinationOrganizationName
    The Azure DevOps organization name as it is visible in the URL, of the destination organization.
    .PARAMETER SourceProjectName
    The Azure DevOps project name of the source repos.
    .PARAMETER SourceRepoName
    The name of the source repo. If not given, all repos will be migrated.
    .PARAMETER DestinationProjectName
    The Azure DevOps project name where the repos will be moved to.
    .PARAMETER DestinationRepoName
    The name of the destination repo. If not given, the name of the source repo will be used.
    Can only be used if a source repo is given.
    .EXAMPLE
    Invoke-AzDoRepoMigration -UserName user@mail.com -Token $token -OrganizationName "exampleOrg" -SourceProjectName "SourceProject" -SourceRepoName "srcRepo" -DestinationProjectName "DestinationProject"
    ===
    Will move the repo srcRepo from SourceProject to DestinationProject. The repo name will remain the same.
    .EXAMPLE
    Invoke-AzDoRepoMigration -UserName user@mail.com -Token $token -OrganizationName "exampleOrg" -SourceProjectName "SourceProject" -DestinationProjectName "DestinationProject"
    ====
    Will move all repos from SourceProject to DestinationProject.
    .NOTES
    Created by: Barbara Forbes
    @Ba4bes
    with help from https://stackoverflow.com/questions/56916593/azure-devops-import-git-repositories-requiring-authorization-via-api
    .LINK
    https://4bes.nl/2021/07/25/migrate-azure-devops-repos-with-powershell/
    #>
    param(
        [Parameter(Mandatory = $true)]
        [String]$SourceUserName ,
        [Parameter(Mandatory = $true)]
        [String]$DestinationUserName ,
        [Parameter(Mandatory = $true)]
        [String]$SourceToken  ,
        [Parameter(Mandatory = $true)]
        [String]$DestinationToken  ,
        [Parameter(Mandatory = $true)]
        [String]$SourceOrganizationName  ,
        [Parameter(Mandatory = $true)]
        [String]$DestinationOrganizationName  ,
        [Parameter(Mandatory = $true)]
        [String]$SourceProjectName  ,
        [Parameter(Mandatory = $false)]
        [String]$SourceRepoName,
        [Parameter(Mandatory = $true)]
        [String]$DestinationProjectName  ,
        [Parameter(Mandatory = $false)]
        [String]$DestinationRepoName
    )

    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $SourceUserName, $SourceToken)))
    $SourceHeader = @{
        Authorization = ("Basic {0}" -f $base64AuthInfo)
    }
    $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $DestinationUserName, $DestinationToken)))
    $DestinationHeader = @{
        Authorization = ("Basic {0}" -f $base64AuthInfo)
    }
    $SourceURLBase = "https://dev.azure.com/$SourceOrganizationName"
    $DestinationURLBase = "https://dev.azure.com/$DestinationOrganizationName"

    Write-Verbose "INFO: Starting with project $SourceProjectName in organization $SourceOrganizationName"
    $SourceRepositoryURL = "$SourceURLBase/$SourceProjectName/_apis/git/repositories?api-version=6.0"

    # Collect all Repo's by default.
    Try {
        $AllSourceRepos = (Invoke-RestMethod $SourceRepositoryURL -Headers $SourceHeader).value | Where-Object { $_.isDisabled -eq $false }
    }
    Catch {
        if ($_ -match "Access Denied") {
            Throw "Access has been denied, please check your token"
        }
        else {
            Throw $_
        }
    }
    # if a specific repo is specified, only that repo will be collected.
    if ($SourceRepoName) {
        Write-Verbose "Found SourceRepoName: $SourceRepoName"
        $AllSourceRepos = $AllSourceRepos | Where-Object { $_.name -eq $SourceRepoName }
    }
    Write-Verbose "Found $($AllSourceRepos.Count) repos"
    $LoopCount = 0
    foreach ($SourceRepo in $AllSourceRepos) {
        $LoopCount++
        Write-Verbose "INFO: Starting with repo $($SourceRepo.name)"
        $SourceRepoName = $SourceRepo.name
        # Check if the repo is not empty.
        try {
            $null = Invoke-RestMethod "$($SourceRepo.url)/items?recursionLevel=Full&api-version=6.0" -Headers $SourceHeader -Erroraction stop
            $Errormessage = "none"
        }
        catch {
            $Errormessage = $_.ErrorDetails.Message

        }
        if ($Errormessage -like "*Cannot find any branches*" ) {
            Write-Verbose "INFO: Repo is empty"
        }
        else {
            # Start the import process.

            $EndpointURL = "$DestinationURLBase/$DestinationProjectName/_apis/serviceendpoint/endpoints?api-version=5.1-preview.2"

            # create endpoint
            $ServiceConnection = Invoke-RestMethod $EndpointURL -Headers $DestinationHeader
            if ( ($ServiceConnection).value.name -contains "Git Import") {
                Write-Verbose "INFO: ServiceConnection already exists"
                $Endpoint = $ServiceConnection.value
            }
            else {
                Write-Verbose "INFO: Creating ServiceConnection"
                $Body = @{

                    "name"          = "Git Import"
                    "type"          = "git"
                    "url"           = "https://$DestinationOrganizationName@dev.azure.com/$DestinationOrganizationName/$SourceProjectName/_git/$SourceRepoName"

                    "authorization" = @{
                        "parameters" = @{
                            "username" = "$SourceUserName"
                            "password" = "$SourceToken"
                        }
                        "scheme"     = "UsernamePassword"
                    }
                }
                $Parameters = @{
                    Uri         = $EndpointURL
                    Method      = "POST"
                    ContentType = "application/json"
                    Headers     = $DestinationHeader
                    Body        = ( $Body | ConvertTo-Json )
                }
                Try {
                    $Endpoint = Invoke-RestMethod @Parameters
                }
                Catch {
                    Throw "Could not create Endpoint: $_"
                }
            }
            # Check if the repo already exists
            if (!$DestinationRepoName) {
                $DestinationRepoName = $SourceRepoName
            }

            $RepoURL = "$DestinationURLBase/$DestinationProjectName/_apis/git/repositories?api-version=6.0"

            $DestinationRepos = (Invoke-RestMethod $RepoURL -Headers $DestinationHeader).value
            if ($DestinationRepos.name -contains $DestinationRepoName) {
                Write-Verbose "Repo already exists, skipping"
            }
            else {
                Write-Verbose "Creating Repo"

                $Body = @{

                    "name" = $DestinationRepoName

                }
                $Parameters = @{
                    uri         = "$DestinationURLBase/$DestinationProjectName/_apis/git/repositories/?api-version=5.0"
                    Method      = 'POST'
                    ContentType = "application/json"
                    Headers     = $DestinationHeader
                    Body        = ($Body | ConvertTo-Json)
                }
                Try {
                    Invoke-RestMethod @Parameters | Out-Null
                }
                Catch {
                    Throw "Could not create Repo: $_"
                }

                # import repository
                if ($LoopCount -ge $AllSourceRepos.count) {
                    $deleteServiceEndpointAfterImport = $true
                    Write-Verbose "more repo's coming up, keeping ServiceEndpoint"
                }
                else {
                    $deleteServiceEndpointAfterImport = $false
                    Write-Verbose "Last repo, deleting ServiceEndpoint after import"
                }
                $Body = @{
                    "parameters" = @{
                        "deleteServiceEndpointAfterImportIsDone" = $deleteServiceEndpointAfterImport
                        "gitSource"                              = @{
                            "url"       = "https://$SourceOrganizationName@dev.azure.com/$SourceOrganizationName/$sourceProjectName/_git/$SourceRepoName"
                            "overwrite" = $false
                        }
                        "tfvcSource"                             = $null
                        "serviceEndpointId"                      = $Endpoint.id
                    }
                }

                $Parameters = @{
                    uri         = "$DestinationURLBase/$DestinationProjectName/_apis/git/repositories/$DestinationRepoName/importRequests?api-version=5.0-preview"
                    Method      = 'Post'
                    ContentType = "application/json"
                    Headers     = $DestinationHeader
                    Body        = ($Body | ConvertTo-Json)
                }

                Try {
                    Invoke-RestMethod @Parameters | Out-Null
                }
                Catch {
                    Throw "Could not import Repo: $_"
                }
                Write-Verbose "INFO: Done with Repo $DestinationReponame"
            }
            $DestinationRepoName = $null
        }
    }

    Write-Verbose "INFO: done with project"
}

# Example call to function
Invoke-AzDoRepoMigration -SourceUserName "admin@contoso.com" `
    -DestinationUserName "admin@contoso-new.com" `
    -SourceToken "aaaa" `
    -DestinationToken "bbbb" `
    -SourceOrganizationName "consoso" `
    -DestinationOrganizationName "contoso-new" `
    -SourceProjectName "Website" `
    -DestinationProjectName "Website" `
    -Verbose
