# Azure DevOps Administration scripts

[![Verify scripts](https://github.com/FokkoVeegens/azure-devops-administration/actions/workflows/verify.yml/badge.svg)](https://github.com/FokkoVeegens/azure-devops-administration/actions/workflows/verify.yml)

This repository contains scripts helping to administer Azure DevOps Services and Azure DevOps Server. These are either PowerShell or T-SQL scripts using varying technologies to make changes or to extract data. Use at your own risk.

See the [Contributor guidelines](/.github/CONTRIBUTING.md) to contribute to this code.

# Configuration

Generally I put variables at the top, that need to be configured prior to running the script. One you might run into is the following:
```PowerShell
$pat = Get-Content -Path ".\pat.txt"
```
You'll need a pat.txt file in the working folder, containing just one [Azure DevOps Personal Access Token](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=Windows) and nothing else. It will be used for authentication.
