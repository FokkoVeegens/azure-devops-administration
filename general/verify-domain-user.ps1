$cred = Get-Credential
Add-Type -AssemblyName System.DirectoryServices.AccountManagement
$domain = ($cred.UserName -split "\\")[0]
$PrincipalContext = New-Object System.DirectoryServices.AccountManagement.PrincipalContext ([System.DirectoryServices.AccountManagement.ContextType]::Domain),$domain
$PrincipalContext.ValidateCredentials($cred.UserName,$cred.GetNetworkCredential().Password)
