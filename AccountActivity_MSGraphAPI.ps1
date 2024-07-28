<#
    This script collects information from AD such as last logon date, Azure last successful sign in (interactive / non-interactive).
    Then the results are exported into a .CSV file. The script can be easily modified to ingest data from a .csv file or similar. End goal is 
    to identify inactive accounts. 
#>

Write-Host ("-" * 100)
$ADUserssActivitiesResults = @()

# Global variable to keep track of when the access token will expire
$Global:BearerTokenExpiration = $null

function ConnectMgGraph (){
    # Read-only permission to MS Graph API
    $ClientSecret = "[CLIENT_SECRET]"
    $ClientID = "[CLIENT_ID]"
    $TentantID = "[TENANT_ID]"
    $scope = "https://graph.microsoft.com/.default"  # or any other resource URL you need
    $tokenEndpoint = "https://login.microsoftonline.com/$TentantID/oauth2/v2.0/token"

    # Define the body of the request
    $body = [Ordered] @{
        grant_type    = "client_credentials"
        client_id     = $clientID
        client_secret = $clientSecret
        scope      = $scope
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::tls12
    # Send the request to get the token
    try{
        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method POST -Body $body
        Write-Host "Bearer token successfully retrieved"
    }catch{
        $CustomErrMessage = "The [SCRIPT_NAME].ps1 script failed to retrieve a bearer token to authenticate to the MS Graph API. The following error has occured:"
        $PSErrMessage = $Error[0]
        
        Write-Host "Unable to retrieve bearer token. Error: $PSErrMessage"
        Exit 1
    }

    # Extract the access token from the response
    $accessToken = $response.access_token
    $parts = $accessToken -split '\.'

    # Convert JWT token into a format that can be converted to JSON, allowing the script to retrieve the token's expiration time
    if ($parts.Length -ne 3) {
        $CustomErrMessage = "The [SCRIPT_NAME].ps1 script failed to retrieve access token expiration date. The JWT token format isn't proper"
        $PSErrMessage = $Error[0]
        
        Write-Host "Unable to retrieve access token expiration date, JWT token not in the correct format"
        Exit 1
    }

    $base64Url = $parts[1]
    $base64 = $base64Url.Replace('_', '/').Replace('-', '+')

    switch ($base64.Length % 4) {
        2 { $base64 += '==' }
        3 { $base64 += '=' }
    }

    $jwtToJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($base64))
    $jwtFromJson = $jwtToJson | ConvertFrom-Json
    # Set a global variable with the bearer access token expiration, which will be checked in the 'for' loop below to see if it expires, and if so, refresh it
    $global:BearerTokenExpiration = ([System.DateTimeOffset]::FromUnixTimeSeconds($jwtFromJson.exp)).LocalDateTime
    Write-Host "Access token will expire on $BearerTokenExpiration"

    $securedAccesToken = $accessToken | ConvertTo-SecureString -AsPlainText -Force

    try{
        Connect-MgGraph -AccessToken $securedAccesToken -NoWelcome
        Write-Host "Successfully connected to MS Graph API"
    }catch{
        $CustomErrMessage = "The [SCRIPT_NAME].ps1 script failed to launch the <b>Connect-MgGraph</b> cmdlet. The following error has occured:"
        $PSErrMessage = $Error[0]
        
        Write-Host "Unable to connect to MS Graph API. Error: $PSErrMessage"
        Exit 1
    }
}

# Call function to connect to MS Graph API
ConnectMgGraph

try{
    $GroupName =  Get-ADGroup -Identity "[GROUP_NAME]" -Properties Member | Select-Object -ExpandProperty Member | Get-ADUser -Properties SamAccountName, EmployeeID, PasswordExpired, PasswordLastSet, LastLogonDate
    Write-Host "Successfully retrieved members of the '[GROUP_NAME]' group"
}catch{
    $CustomErrMessage = "The [SCRIPT_NAME].ps1 script failed to retrieve members of the '[GROUP_NAME]' group. The following error has occured:"
    $PSErrMessage = $Error[0] | Out-String
    
    Write-Host "Unable to retrieve members of '[GROUP_NAME]' group. Error: $PSErrMessage"
}

Write-Host "Retrieving AD data and checking default password for users"
Write-Host "Checking information for $($GroupName.count) users"

foreach ($ADUsers in $GroupName){
    $DS = New-Object System.DirectoryServices.AccountManagement.PrincipalContext('domain')
    # If token will expire within the next 5 minutes, call ConnectMgGraph function to request a new ones
    $BearerTokenTimeMinutesLeft = ($BearerTokenExpiration - (Get-Date)).Minutes

    if ($BearerTokenTimeMinutesLeft -lt 5){
        Write-Host "-" * 100
        Write-Host "Access bearer token expiring within 5 minutes, refreshing token"
        ConnectMgGraph
        Write-Host "Access token refreshed"
        Write-Host "-" * 100
    }

    $Username = $ADUsers.SamAccountName
    $Email = $ADUsers.Email
    $TempPassword = "[TEMP_PASSWORD]"
    $PasswordExpired = $ADUsers.PasswordExpired
    $PasswordLastSet = $ADUsers.PasswordLastSet
    $LastLogonDate = $ADUsers.LastLogonDate

    $AzureLastSignDateTime = (Get-MgUser -Filter "startswith(UserPrincipalName, '$Email')" -Select SignInActivity | Select-Object -ExpandProperty SignInActivity).LastSignInDateTime

    $ADUserssActivitiesResults += New-Object psobject -Property @{
        "Username" = $Username
        "PasswordExpired" = $PasswordExpired
        "PasswordLastSet" = $PasswordLastSet
        "LastLocalADLogonDate" = $LastLogonDate
        "AzureLastSignInDateTime" = $AzureLastSignDateTime
    }
}

$Date = Get-Date -Format "MMddyyyy_Hmms"
$ExportPath = "ActivityResults_$Date.csv"
$ADUserssActivitiesResults | Export-Csv -Path $ExportPath -NoTypeInformation
