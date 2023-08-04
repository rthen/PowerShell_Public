<#
    Script obtains a list of users who have email forwarding enabled, as well as any inbox rules
    that forwards / redirects emails (regardless if it is an internal or external user).

    Script can be modified to scan subset of mailboxes, or all mailboxes in a tentant. 
#>

Connect-ExchangeOnline

$GroupA = (Get-ADGroupMember -Identity "GroupA" | Select-Object SamAccountName).SamAccountName
$GroupB = (Get-ADGroupMember -Identity "GroupB" | Select-Object SamAccountName).SamAccountName
$GroupAListCount = $GroupAList.count
$GroupBListCount = $GroupBList.count

$GroupAResults = @()
$GroupBResults = @()

$TotalGroupA = 1
$TotalGroupB = 1

foreach ($User in $GroupA){
    Write-Host "Checking user $User ---> $$TotalGroupA / $GroupAListCount" -ForegroundColor Green
    $UPN = $User + "@domain" # CHANGE

    $ForwardingAddresses = Get-Mailbox -Identity $UPN | Select-Object ForwardingSmtpAddress, ForwardingAddress
    $InboxRules = Get-InboxRule -Mailbox $UPN
    $ForwardToRules = $InboxRules | Where-Object {$_.ForwardTo -ne $Null} | Select-Object ForwardTo
    $RedirectToRules = $InboxRules | Where-Object {$_.ForwardTo -ne $Null} | Select-Object RedirectTo

    $GroupAResults += New-Object psobject -Property @{
        "UPN" = $UPN
        "ForwardingSmtpAddress" = $ForwardingAddresses.ForwardingSmtpAddress | Out-String
        "ForwardingAddress" = $ForwardingAddresses.ForwardingAddress | Out-String
        "InboxRuleForwardTo" = $ForwardToRules.ForwardTo | Out-String
        "RedirectTo" = $ForwardToRules.RedirectTo | Out-String
    }
    $TotalGroupA++
}

foreach ($User in $GroupB){
    Write-Host "Checking user $User ---> $TotalGroupB / $GroupBListCount" -ForegroundColor Green
    $UPN = $User + "@domain" # CHANGE

    $ForwardingAddresses = Get-Mailbox -Identity $UPN | Select-Object ForwardingSmtpAddress, ForwardingAddress
    $InboxRules = Get-InboxRule -Mailbox $UPN
    $ForwardToRules = $InboxRules | Where-Object {$_.ForwardTo -ne $Null} | Select-Object ForwardTo
    $RedirectToRules = $InboxRules | Where-Object {$_.ForwardTo -ne $Null} | Select-Object RedirectTo

    $GroupBResults += New-Object psobject -Property @{
        "UPN" = $UPN
        "ForwardingSmtpAddress" = $ForwardingAddresses.ForwardingSmtpAddress | Out-String
        "ForwardingAddress" = $ForwardingAddresses.ForwardingAddress | Out-String
        "InboxRuleForwardTo" = $ForwardToRules.ForwardTo | Out-String
        "RedirectTo" = $ForwardToRules.RedirectTo | Out-String
    }
    $TotalGroupB++
}

$GroupAResults | Export-Csv -Path "GroupA_EmailForwarding.csv" -NoTypeInformation
$GroupBResults | Export-Csv -Path "GroupB_EmailForwarding.csv" -NoTypeInformation
