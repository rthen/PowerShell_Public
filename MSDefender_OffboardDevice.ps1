<#
  Script takes a .csv file that contains the email address of the user who owns the device (owner device defined by Intune), 
  the user's distinguishedname within local AD, the Microsoft Defender ID (MDFID), the device name, the distinguishedname of the computer object within
  local AD, and the Azure device ID. 

  The only column that really matters is the device's Defender ID. The other columns could be removed, and are mainly for logging purposes.
#>

$TenantId = '[TENANT_ID]'
$AppId = '[APP_ID]'
$AppSecret = "[APP_SECRET]"

$APIEndpoint = "https://api.securitycenter.microsoft.com"

$AuthBody = [Ordered] @{
    resource = $APIEndpoint
    client_id = $appId
    client_secret = $appSecret
    grant_type = 'client_credentials'
}
$OAuthUri = "https://login.microsoftonline.com/$tenantId/oauth2/token"

$AuthResponse = Invoke-RestMethod -Method Post -Uri $OAuthUri -Body $AuthBody -ErrorAction Stop
$Token = $AuthResponse.access_token

$Headers = @{ 
    'Content-Type' = 'application/json'
    Accept = 'application/json'
    Authorization = "Bearer $Token"
}
$Body = ConvertTo-Json -InputObject @{ 'Comment' = "Off boarding device" }

$OffboardDevices = Import-Csv [PATH_TO_CSV]

foreach ($row in $OffboardDevices){
    $DeviceOwnerEmail = $row.DeviceOwnerEmail
    $UserDN = $row.UserDN
    $MDFID = $row.MDFID
    $DeviceName = $row.DeviceName
    $DN = $row.DN
    $AADID = $row.AADID

    Write-Host ("-" * 100) -ForegroundColor Yellow

    Write-Host @"
    Device name: $DeviceName
    Device owner: $DeviceOwnerEmail
    User DN: $UserDN
    Device DN: $DN
"@
    try{

        $OffBoardingUrl = "https://api-us.securitycenter.microsoft.com/api/machines/$MDFID/offboard"
        $WebResponse = Invoke-WebRequest -Method Post -Uri $OffBoardingUrl -Headers $Headers -Body $Body -ErrorAction Stop -UseBasicParsing
        $StatusCode = $WebResponse.StatusCode
        $OffBoardingStatus = (ConvertFrom-Json $WebResponse).Status

        Write-Host @"
        Request status: $StatusCode
        Offboarding status: $OffBoardingStatus
"@
    }catch [System.Net.WebException]{
        $ErrorResponse = $_.Exception.Message
        Write-Host "Request status: $ErrorResponse"
    }catch{
        $Err = $Error[0]
        Write-Host "Unkown Error: $Err"
    }
}
