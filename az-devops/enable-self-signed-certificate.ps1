# Enables running the Azure CLI DevOps extension with an Azure DevOps Server with a self-signed certificate
# Will use chocolatey for installation
# Will install
# * Azure CLI
# * OpenSSL
# * Azure CLI DevOps extension

# Set variables on first 2 lines of the script
# Run this script as admin!!

$AzureDevOpsUrl = "https://devops.local:443"
$CertificateIndex = 2 # The index of the root certificate in the chain. If the chain has 3 certificates, the index of the root certificate is 2
$CertificateStorePath = "$($env:USERPROFILE)\AzDevOpsCertificates"

function Write-Msg([Parameter(Position = 0)][ValidateSet("I", "W", "E", "S")][string]$level, [Parameter(Position = 1)][string]$message) {
    [System.ConsoleColor]$color = [System.ConsoleColor]::DarkGray
    switch ($level) {
        "W" { 
            $color = [System.ConsoleColor]::Yellow
            break
        }
        "E" {
            $color = [System.ConsoleColor]::Yellow
            break
        }
        "S" {
            $color = [System.ConsoleColor]::Green
            break
        }
    }
    Write-Host -Object $message -ForegroundColor $color
    if ($level -eq "E") {
        exit 1
    }
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") +
    ";" +
    [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# Check if Chocolatey is installed
Write-Msg I "Verifying if Chocolatey is installed"
$chocoExePath = Join-Path -Path $env:ChocolateyInstall -ChildPath "choco.exe"
if ([string]::IsNullOrEmpty($env:ChocolateyInstall) -or (!(Test-Path -Path $chocoExePath -PathType Leaf))) {
    Write-Msg E "Chocolatey cannot be found. Ensure it is installed (https://www.chocolatey.org)"
}
else {
    Write-Msg I "Chocolatey install found"
}

# Install OpenSSL Light using Chocolatey
choco install openssl.light -y
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 3010) {
    Write-Msg E "OpenSSL Light failed to install, please check the outcome above this message and fix any issues $($LASTEXITCODE)"
}
else {
    Write-Msg I "OpenSSL Light installed successfully or was already installed"
}

# Install Azure CLI using Chocolatey
choco install azure-cli -y
if ($LASTEXITCODE -ne 0) {
    Write-Msg E "Azure CLI failed to install, please check the outcome above this message and fix any issues $($LASTEXITCODE)"
}
else {
    Write-Msg I "Azure CLI installed successfully or was already installed"
}

# Refresh environment in order to have access to Azure CLI commands
Refresh-Path

# Add Azure DevOps extension to AZ
Write-Msg I "Installing AZ DevOps extension"
az extension add --name azure-devops
if ($LASTEXITCODE -ne 0) {
    Write-Msg E "The installation of the AZ DevOps extension failed, please check the outcome above this message and fix any issues $($LASTEXITCODE)"
}
else {
    Write-Msg I "The installation of the AZ DevOps extension succeeded or it was already installed"
}

# Request website
Write-Msg I "Executing request to site $($AzureDevOpsUrl)"
$WebRequest = [Net.WebRequest]::CreateHttp($AzureDevOpsUrl)
$WebRequest.AllowAutoRedirect = $true
$chain = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Chain
[Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

try { 
    $WebRequest.GetResponse()
    Write-Msg I "Request made successfully"
}
catch {
    # No catch, we need to retrieve the certificate only
}

# Creates Certificate
Write-Msg I "Retrieving certificate from response"
$Certificate = $WebRequest.ServicePoint.Certificate.Handle

# Build chain
Write-Msg I "Building chain of certificates"
$chain.Build($Certificate)        
[Net.ServicePointManager]::ServerCertificateValidationCallback = $null
$bytes = $chain.ChainElements[$CertificateIndex].Certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)

# Write Certificate file
$certificateFile = Join-Path -Path $CertificateStorePath -ChildPath "azdevops.cer"
New-Item -Path $CertificateStorePath -ItemType Directory -Force | Out-Null
Write-Msg I "Writing root certificate to file: $($certificateFile)"
Set-Content -Value $bytes -Encoding byte -Path $certificateFile

# Convert certificate to .pem file
Write-Msg I "Converting certificate to .pem file"
$pemFile = Join-Path -Path $CertificateStorePath -ChildPath "azdevops.pem"
openssl x509 -inform der -in $certificateFile -out $pemFile
if ($LASTEXITCODE -ne 0) {
    Write-Msg E "Failed to convert, please check the outcome above this message and fix any issues $($LASTEXITCODE)"
}
else {
    Write-Msg I "Successfully converted certificate"
}

# Set necessary environment variables
Write-Msg I "Writing required system variables"
[Environment]::SetEnvironmentVariable("REQUESTS_CA_BUNDLE", $pemFile, [System.EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("ADAL_PYTHON_SSL_NO_VERIFY", 1, [System.EnvironmentVariableTarget]::Machine)
[Environment]::SetEnvironmentVariable("AZURE_CLI_DISABLE_CONNECTION_VERIFICATION", 1, [System.EnvironmentVariableTarget]::Machine)

# Make them work for the current session as well
[Environment]::SetEnvironmentVariable("REQUESTS_CA_BUNDLE", $pemFile, [System.EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable("ADAL_PYTHON_SSL_NO_VERIFY", 1, [System.EnvironmentVariableTarget]::Process)
[Environment]::SetEnvironmentVariable("AZURE_CLI_DISABLE_CONNECTION_VERIFICATION", 1, [System.EnvironmentVariableTarget]::Process)

# Refresh the environment to have the system variables
Refresh-Path

# Motivate user to login:
Write-Msg S "The installation and configuration succeeded, 'az devops login' will now be started, you need to provide the Personal Access Token (PAT) for the environment you will be using"
az devops login
