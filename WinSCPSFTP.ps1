<#
This script uses WinSCP to upload files from a local to a remote server using SFTP. Additionally, the script
will alert one or more administrator of any errors in order to reduce the amount of time the script is not properly working. 

To get started:
1-Install WinSCP app
2-Install WinSCP .NET module. It is Required to interact with the WinSCP networking commands along with PowerShell

If the script fails at importing the .dll, right click the .dll--> click properties-->unblock .dll(If blocked)-->if blocked, unblock, signout and sign in again
#>

Add-Type -Path "C:\Program Files (x86)\WinSCP\WinSCPnet.dll" # Loads .NET module
$ErrorActionPreference = "Stop"  # Allows 'catch' to work

function LogIt{
    <#
        .SYNOPSIS 
          Creates a log file in the CMTrace format
        .DESCRIPTION
            Function that logs the operational running status of script
        .EXAMPLE
             Example LogIt function calls
             LogIt -message ("Starting Logging Example Script") -component "Main()" -type Info 
             LogIt -message ("Log Warning") -component "Main()" -type Warning 
             LogIt -message ("Log Error") -component "Main()" -type Error
             LogIt -message ("Log Verbose") -component "Main()" -type Verbose
             LogIt -message ("Script Status: " + $Global:ScriptStatus) -component "Main()" -type Info 
             LogIt -message ("Stopping Logging Example Script") -component "Main()" -type Info
              LogIt -message ("Stopping Logging Example Script") -component "Main()" -type Info -LogFile a.log
    #>
   param (
        [Parameter(Mandatory=$true)]
        [string]$message,
        [Parameter(Mandatory=$true)]
        [string]$component,
        [Parameter(Mandatory=$true)]
         [ValidateSet("Info","Warning","Error")] 
        [string]$type,
         [string]$LogFile = "PATH_TO_LOG_FILE"
    )
   $MaxLogSizeInKB = 10000
  
   if ($type -eq "Error"){
       $toLog = "{0} `$$<{1}><{2} {3}><thread={4}>" -f ($type + ": " + $message), ($Global:ScriptName + ":" + $component), (Get-Date -Format "MM-dd-yyyy"), (Get-Date -Format "HH:mm:ss.ffffff"), $pid
       $toLog | Out-File -Append -Encoding UTF8 -FilePath $LogFile
       Write-Host $message -foreground "red"
   }
   elseif ($type -eq "Warning"){
       $toLog = "{0} `$$<{1}><{2} {3}><thread={4}>" -f ($type + ": " + $message), ($Global:ScriptName + ":" + $component), (Get-Date -Format "MM-dd-yyyy"), (Get-Date -Format "HH:mm:ss.ffffff"), $pid
       $toLog | Out-File -Append -Encoding UTF8 -FilePath $LogFile
       Write-Host $message -foreground "yellow"
   }
   elseif ($type -eq "Info"){
       $toLog = "{0} `$$<{1}><{2} {3}><thread={4}>" -f ($message), ($Global:ScriptName + ":" + $component), (Get-Date -Format "MM-dd-yyyy"), (Get-Date -Format "HH:mm:ss.ffffff"), $pid
       $toLog | Out-File -Append -Encoding UTF8 -FilePath $LogFile
       Write-Host $message -foreground "white"
   }	
   if ((Get-Item $LogFile).Length/1KB -gt $MaxLogSizeInKB){ 
       $log = $LogFile
       Rename-Item $LogFile ($log.Replace(".log", "_ROTATED_" + (Get-Date).ToString('MMddyyhhmm') + ".log")) -Force
   }
} 

function SendEmailNotification($hostname, $errormessage){ # Send email notification if error occurs.
    <#
    .DESCRIPTION
        Function that sends email alerts to one or more email address using a local or hosted SMTP relay server
    #>
    try{
        $noParams = @{
            Body = @"
                    <img src="OPTIONAL_IMAGE OF COMPANY LOGO">
                    <p>$errormessage
                    <p>Please view 'OPTIONAL_LOG PATH' for further troubleshooting.
                
"@ 
            Subject = "Failed to transfer files to $hostname"
            From = "FROM_ADDRESS" # CHANGE
            To = @("TO_ADDRESS", "TO_ADDRESS") # Array if wanting to send email to more than one user
            SmtpServer = "RELAY_SERVER" # CHANGE
        }
        Send-MailMessage @noParams -BodyAsHtml
    LogIt -message "Sent TO_WHOM notification" -component ("SendEmailNotification:55") -type Warning
    }catch{
        Logit -message "Failed to send TO_WHOM notification" -component ("SendEmailNotification:55") -type Warning
    }
}

function UploadFiles($hostname, $username, $source_location, $dest_location, $key){ # KEY REQUIRED
    <#
    .DESCRIPTION
        Copies given files from one location to a remote server through SFTP. Must provide 4 arguments to the function:
            1-The remove server name in which the files will be moved to
            2-The username which SFTP will be using to transfer files
            3-The full path of the file(s) that are being transferred
            4-The full path where the files will be copied to
    #>
     try{
        if (Test-Path $source_location){
            LogIt -message ("File(s) found. Starting SFTP transfer") -component "UploadFiles:72" -type Info

            $sessionOptions = New-Object WinSCP.SessionOptions -Property @{ # Values submitted to WinScp
                Protocol = [WinSCP.Protocol]::Sftp
                HostName = $hostname
                Username = "USERNAME" # CHANGE
                SecurePassword = Get-Content "PATH_OF_HASHED_PASSWORD" | ConvertTo-SecureString # CHANGE
                SshHostKeyFingerprint = $key 
            }
    
            try{ # Creates connection
                $session = New-Object WinSCP.Session
                $session.SessionLogPath = "PATH_TO_LOG_FILE" # CHANGE
                $session.Open($sessionOptions)
                LogIt -message ("Opening SFTP session") -component "UploadFiles:89" -type Info

                $transferOptions = New-Object WinSCP.TransferOptions
                $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary
                $transferResult = $session.PutFiles($source_location, $dest_location, $False, $transferOptions) # $False does not delete file after transfer

                # Throw any error if transfer fail
                $transferResult.Check()
                
            }finally{    
                $session.Dispose() # Closes connection whether file was sucessfully transferred or not
                LogIt -message ("Closing SFTP session: $Session") -component "UploadFiles:101" -type Info
            }
            
        }else{ # Do nothing if no files were found
            LogIt -message ("No files found to transfer, skipping....") -component "UploadFiles:100" -type Info
        }
    }catch{
            $errormessage = "<b>The following error has ocurred:</b> <p>`n$_.Exception.Message"
            SendEmailNotification $hostname $errormessage
            exit 0
    }
}

<#
UploadFiles "SERVER_ADDRESS OR NAME" "USERNAME" "SOURCE FILE/PATH" "DESTINATION PATH" "PUBLIC SSH KEY".
If no ssh key fingerprint available, set 'GiveUpSecurityAndAcceptAnySshHostKey = "$true"' on $sessionOptions
#>

UploadFiles "SERVER_ADDRESS" "USERNAME" "PATH_OF_FILES_TO_MOVE" "REMOTE_PATH" 'SSH_KEY_FINGERPRINT'


$LogFile = "PATH_TO_LOG_FILE"
$MaxLogSizeInKB = 10000

# If SFTPOperation.log greater than 1000KB, let's rename it and use a new .log file
try{
    if ((Get-Item $LogFile).Length/1KB -gt $MaxLogSizeInKB){
        $log = $LogFile
        Rename-Item $LogFile ($log.Replace(".log", "_ROTATED_" + (Get-Date).ToString('MMddyyhhmm') + ".log")) -Force
    }
}catch{
    LogIt -message ("WinScpperational.log file cannot be renamed. Either the file does not exists or another process is using it") -component "SFTP_Connection.ps1:125" -type Warning
 }
