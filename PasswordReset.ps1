Import-Module ActiveDirectory
Import-Module MSOnline
Connect-MsolService

Function password_reset(){
    <#
    .SYNOPSIS
        Resets user's password
    .DESCRIPTION
    Connects to MSOnline to reset the password of a given user to a random password of 15 characters. It also resets the password of the user locally as well if environemnt is hybrid.
    Since synchronization between Azure AD and a local DC might take 30 mins or more, password will be reset on both locations.
    This is a quick solution to deal with a compromised account and reduce the likelyhood of phishing emails being sent out from the compromised account and more. 
    #>
    $user_name = Read-Host -Prompt 'Enter the username whose password is being reset'

    Try{
        $dp_name = (get-aduser $user_name -Properties * | Select-Object DisplayName).DisplayName # Obtains Last and First name while getting rid of table like format
        $RandomPassword = (-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 15 | % {[char]$_}))

        Set-MsolUserPassword -UserPrincipalName "$user_name@wit.edu" -NewPassword $RandomPassword -ForceChangePassword $True
        Set-ADAccountPassword -Identity "$user_name" -NewPassword (ConvertTo-SecureString -AsPlainText "$RandomPassword" -Force)
        Write-Host "Password has been reset for: $dp_name" -ForegroundColor Green
        Write-Host "Password has been set to: $RandomPassword" -ForegroundColor Green

        $retry = read-host -Prompt 'Do you want to reset the password of another user?(Y/N)'

        if ($retry.tolower() -eq 'y'){
            password_reset
        }else{
           exit
        }

    }Catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        Write-Host "The username does not exists, please check the spelling" -ForegroundColor Yellow
        $action = Read-Host -Prompt "Do you wish to retry?(y/n)"

        if ($action -eq "y"){
            password_reset

        } else{
            Read-Host -Prompt "Please press enter to exit out of the program"    
        } 
    }Catch [UnauthorizedAccessException]{ 
            Write-Host "Acess denied! Cannot reset the password for '$user_name'" -ForegroundColor Red
            Write-Host "Either the user's account is disabled and must be enabled first or you do not have permissions to reset the user's password"
            Read-Host -Prompt "Press enter to exit"      
    }Catch {
        Write-Host "The following error has occurred: " $Error[0] -ForegroundColor Red
        Read-Host -Prompt "Press enter to exit"
    }
}

password_reset # Calls function
