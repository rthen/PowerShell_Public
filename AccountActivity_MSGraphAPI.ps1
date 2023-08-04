<#
  Script connects to MS Graph API, Exchange online, and local AD to retrieve activity related data for accounts. 
  This script can check things such as the last sign in history within Azure or local AD, which can be useful at identifying ghost accounts
#>
try{    
    Connect-ExchangeOnline -ShowBanner:$false # Module used to pull Exchange online related information
}catch{
    $Err = $Error[0] | Out-String
    Write-Host "Error connecting to Exchange Online: $Err" -ForegroundColor Red
    Exit 1
}

try{
    Write-Host "***** Connecting to MS Graph API *****" -ForegroundColor Yellow
    $ClientID = '[CLIENT_ID]'
    $TentantID = '[TENTANT_ID]'
    $SelfSignedCertThumbprint = "[CERT_THUMBPRINT]" # Self signed certificate located on personal cert store

    Connect-MgGraph -ClientID $ClientID -TenantId $TentantID -CertificateThumbprint $SelfSignedCertThumbprint
    Select-MgProfile -Name "beta" # SignIn filtering data is currently in beta, so script must connect to such profile

}catch{
    $Err = $Error[0] | Out-String
    Write-Host "Error connecting to MS Graph API: $Err" -ForegroundColor Red
    Exit 1
}

[System.Collections.ArrayList]$ActivityResults = @()
Write-Host "***** Retrieving all users from local Active Directory, please wait... *****" -ForegroundColor Yellow
$LocalADInfo = Get-ADUser -Filter * -Properties GivenName, Surname, EmployeeID, Description, LastLogonDate, Enabled, PasswordExpired, DistinguishedName, UserPrincipalName, PasswordLastSet, SamAccountName
$Total = 1
$LocalADInfoCount = $LocalADInfo.count
$ErrorActionPreference = "Stop"

foreach ($ADObject in $LocalADInfo){
    Write-Host ("#" * 100) -ForegroundColor Green
    
    $UPN = $ADObject.UserPrincipalName
    $GivenName = $ADObject.GivenName
    $Surname = $ADObject.Surname
    $EmployeeID = $ADObject.EmployeeID
    $Description = $ADObject.Description
    $LastLogonDate = $ADObject.LastLogonDate
    $Enabled = $ADObject.Enabled
    $PasswordExpired = $ADObject.PasswordExpired
    $DistinguishedName = $ADObject.DistinguishedName
    $PasswordLastSet = $ADObject.PasswordLastSet
    $SamAccountName = $ADObject.SamAccountName

    # EOL and Azure attributes will be set to none at first, and updated later on if such information is available
    $EOLLastInteractionTime = "None"
    $EOLLastLogonTime = "None"
    $EOLLastUserAccessTime = "None"
    $EOLLastUserActionTime = "None"
    $AzureLastNonInteractiveSignInDateTime = "None" 
    $AzureLastSignInDateTime = "None"

    # User's with an UPN of '@doman.com' will be switched in Azure to have an UPN of '@domain.com'. Although unlikely that there is a sign in
    # history for such accounts in Azure since they are mostly for service accounts, still worth checking it out.
    if ($UPN -like "*@DOMAIN.COM"){
        $UPN = ($UPN -split "@")[0] + "@domain.com"
    }elseif ($UPN -eq $null){
        # Some accts such as krbtgt does not have an UPN, so UPN will be empty.
        # Running Get-MgUser against empty string will error out, even if in a try/catch when running as a script.
        $UPN = "NullNull"
    }
    
    Write-Host "Checking $UPN (UPN) - $SamAccountName (SamAccountName) - $Total / $LocalADInfoCount" -ForegroundColor Yellow
    try{
        $MailboxStats = Get-MailboxStatistics -Identity $UPN -ErrorAction "Stop" | Select-Object LastInteractionTime, LastLogonTime, LastUserAccessTime, LastUserActionTime
        $EOLLastInteractionTime = $MailboxStats.LastInteractionTime
        $EOLLastLogonTime = $MailboxStats.LastLogonTime
        $EOLLastUserAccessTime = $MailboxStats.LastUserAccessTime
        $EOLLastUserActionTime = $MailboxStats.LastUserActionTime
    }catch{
        Write-Host "Account does not have an active mailbox" -ForegroundColor Red
    }
    
    try{
        $AzureLastSignIn = Get-MgUser -Filter "startswith(UserPrincipalName, '$UPN')" -Select SignInActivity | Select-Object -ExpandProperty SignInActivity
    }catch{
        Write-Host "Unable to find account in Azure" -ForegroundColor Red
    }
    # It's possible the UPN might be on a different format, or the account isn't being synced over to Azure AD. This checks if anything is returned, even if the dates are empty
    if ($AzureLastSignIn){
        $LastNonInteractiveSignInDateTime = $AzureLastSignIn.LastNonInteractiveSignInDateTime
        $LastSignInDateTime = $AzureLastSignIn.LastSignInDateTime
        # Dates pulled from the API are UTC time, so they must be converted to the local time set on the endpoint the script is running in (e.g., EST)
        if ($LastNonInteractiveSignInDateTime){
            $AzureLastNonInteractiveSignInDateTime = $LastNonInteractiveSignInDateTime.ToLocalTime()
        }
        if ($LastSignInDateTime){
            $AzureLastSignInDateTime = $LastSignInDateTime.ToLocalTime()
        }
    }
    $ActivityResults += New-Object psobject -Property @{
        "UPN" = $UPN
        "GivenName" = $GivenName
        "Surname" = $Surname
        "EmployeeID" = $EmployeeID
        "LocalADDescription" = $Description
        "LocalADLastLogonDate" = $LastLogonDate
        "ADAccountEnabled" = $Enabled
        "PasswordExpired" = $PasswordExpired
        "DistinguishedName" = $DistinguishedName
        "LocalADPasswordLastSet" = $PasswordLastSet
        "SamAccountName" = $SamAccountName
        "EOLLastInteractionTime" = $EOLLastInteractionTime
        "EOLLastLogonTime" = $EOLLastLogonTime
        "EOLLastUserAccessTime" = $EOLLastUserAccessTime
        "EOLLastUserActionTime" = $EOLLastUserActionTime
        "AzureLastNonInteractiveSignInDateTime" = $AzureLastNonInteractiveSignInDateTime
        "AzureLastSignInDateTime" = $AzureLastSignInDateTime
    }
    $Total++
}
$Date = Get-Date -Format "MMddyyyy"
$ActivityResults | Export-Csv -Path ADAccountActivity_$Date.csv -NoTypeInformation
