<#
Get every single disabled user object that is part of any groups other than the built in "Domain Users".
#>

$OU = "OU_PATH"
$StartTime = (Get-Date).Millisecond

$Staff = @(Get-ADUser -Filter *)
$BadUsers = @()
$TotalADOjects = 0

foreach ($User in $Staff.samaccountname){
     $TotalADOjects++
     $UserStatus = (Get-ADUser $user -Properties * | select enabled, employeeid)
     
     $TotalGroups = @()
     $GroupMembership = @(Get-ADPrincipalGroupMembership -Identity $User | select name).name
     
     if ($UserStatus.enabled -eq $False){
          if ($GroupMembership.length -gt 1){

               foreach ($Group in $GroupMembership){
                    if ($Group -ne "Domain Users"){
                         $TotalGroups += $group
                    }
               }
               $BadUsers += New-Object psobject -Property @{
                    "Username" = $User
                    "Status" = $UserStatus.enabled
                    "Groups" = ($TotalGroups | out-string)     
               }
          }
     }
}

$BadUsers | Export-Csv -Path "ADGroupCleanUp.csv"
$EndTime = (Get-Date).Millisecond
# Keeping track of a few things for my own knowledge
$TotalRunTime = $EndTime - $StartTime
$TotalADOjects > "totaladobjects.txt"
$TotalRunTime > "runtime.txt"
