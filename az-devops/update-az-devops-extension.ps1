# This script will update the Az DevOps extension (Extension to Azure CLI)
# Specifically in situations where one uses Self Signed Certificates in combination with an on-prem install of Azure DevOps
# Don't forget to set the correct path to the .pem file!

$pemfilepath = "D:\AzureDevOpsCertificate\root_ca.pem"

[Environment]::SetEnvironmentVariable("REQUESTS_CA_BUNDLE", $null, [System.EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("ADAL_PYTHON_SSL_NO_VERIFY", $null, [System.EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("AZURE_CLI_DISABLE_CONNECTION_VERIFICATION", $null, [System.EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("REQUESTS_CA_BUNDLE", $null, [System.EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable("ADAL_PYTHON_SSL_NO_VERIFY", $null, [System.EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable("AZURE_CLI_DISABLE_CONNECTION_VERIFICATION", $null, [System.EnvironmentVariableTarget]::Process)
az extension update --name azure-devops
az devops login
[Environment]::SetEnvironmentVariable("REQUESTS_CA_BUNDLE", $pemfilepath, [System.EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable("ADAL_PYTHON_SSL_NO_VERIFY", 1, [System.EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable("AZURE_CLI_DISABLE_CONNECTION_VERIFICATION", 1, [System.EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable("REQUESTS_CA_BUNDLE", $pemfilepath, [System.EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("ADAL_PYTHON_SSL_NO_VERIFY", 1, [System.EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("AZURE_CLI_DISABLE_CONNECTION_VERIFICATION", 1, [System.EnvironmentVariableTarget]::Machine)
