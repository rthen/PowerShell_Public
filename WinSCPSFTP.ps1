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

function SendEmailNotification($hostname, $ErrMessage){ # Send email notification if error occurs.
    <#
    .DESCRIPTION
        Function that sends email alerts to one or more email address using a local or hosted SMTP relay server
    #>

    $SMTPServer = "SMTP_SERVER" # CHANGE
    $SMTPClient = New-Object System.Net.Mail.SmtpClient($SMTPServer)
    $emailMsg = New-Object System.Net.Mail.MailMessage
    $emailMsg.To.Add("TO_ADDRESS") # CHANGE
    $emailMsg.From = "FROM_DOMAIN" # CHANGE
    $emailMsg.IsBodyHtml = $true
    $attachment = New-Object System.Net.Mail.Attachment -ArgumentList "PATH\TO\IMAGE" # CHANGE
    $attachment.ContentDisposition.Inline = $true
    $attachment.ContentDisposition.DispositionType = "Inline"
    $attachment.ContentType.MediaType = "image/png"
    $attachment.ContentId = "IMAGE_NAME.png" # CHANGE
    $emailMsg.Attachments.add($attachment)

    $emailMsg.Body = @"
    <img id="IMAGE_NAME" src='cid:IMAGENAME.png' alt=''>
    <p> ADD CUSTOM MESSAGE
"@ # CHANGE
    $emailMsg.Subject = "CUSTOM SUBJECT" # CHANGE
    $SMTPClient.send($emailMsg)
    $attachment.Dispose();
    $emailMsg.Dispose();
    LogIt -message ("Error ocurred with the script, sending EMAIL_DOMAIN an email notification") -component SendEmailNotification -type Info
}

function UploadFiles($hostname, $username, $source_location, $dest_location, $KeyFingerPrint){ # KEY REQUIRED
    <#
    .DESCRIPTION
        Copies given files from one location to a remote server through SFTP. Must provide 4 arguments to the function:
            1-The remove server name in which the files will be moved to
            2-The username which SFTP will be using to transfer files
            3-The full path of the file(s) that are being transferred
            4-The full path where the files will be copied to
    #>
     try{
            $sessionOptions = New-Object WinSCP.SessionOptions -Property @{ # Values submitted to WinScp
                Protocol = [WinSCP.Protocol]::Sftp
                HostName = $hostname
                Username = "USERNAME" # CHANGE
                SecurePassword = Get-Content "PATH_OF_HASHED_PASSWORD" | ConvertTo-SecureString # CHANGE
                SshHostKeyFingerprint = $KeyFingerPrint 
            }
    
            try{ # Creates connection
                $session = New-Object WinSCP.Session
                $session.SessionLogPath = "PATH_TO_LOG_FILE" # CHANGE
                $session.Open($sessionOptions)
                LogIt -message ("Opening SFTP session") -component "UploadFiles:112" -type Info

                $transferOptions = New-Object WinSCP.TransferOptions
                $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary
                $transferResult = $session.PutFiles($source_location, $dest_location, $False, $transferOptions) # $False does not delete file after transfer

                # Throw any error if transfer fail
                $transferResult.Check()
                
            }finally{    
                $session.Dispose() # Closes connection whether file was sucessfully transferred or not
                LogIt -message ("Closing SFTP session: $Session") -component "UploadFiles:123" -type Info
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
$datafeed = "PATH_OF_FILES_TO_MOVE"
if (Test-Path -Path $datafeed){
    UploadFiles "SERVER_ADDRESS" "USERNAME" $datafeed "REMOTE_PATH" "SSH_KEY_FINGERPRINT"
}else{
    LogIt -message ("File(s) not found. Skipping SFTP transfer....") -component "SFTP_Connection.ps1" -type Info
}

$ArchiveFolderPath = "PATH_TO_ARCHIVE_FOLDER"

# Checks archive folder and deletes files older than 180 days
Try{
    Get-ChildItem -Path $ArchiveFolderPath -Recurse | Where-Object LastWriteTime -lt (Get-Date).AddDays(-180) | Remove-Item -Force
    LogIt -message ("#" * 200) -component " " -type INFO
    LogIt -message ("Deleting archived files older than 180 days ") -component "SFTP_Connection:151" -type INFO
}Catch{
    LogIt -message ("Failed to delete files in the archive folder of 180 days older or more") -component "SFTP_Connection:168" -type ERROR
}

# Checks log folder and deletes files older than 180 days
$LogFileFolder = "PATH_TO_LOG_FOLDER"
Try{
     Get-ChildItem -Path $LogFileFolder -Recurse | Where-Object LastWriteTime -lt (Get-Date).AddDays(-180) | Remove-Item -Force
     LogIt -message ("Deleting log files older than 180 days ") -component "SFTP_Connection:161" -type INFO
     LogIt -message ("#" * 200) -component " " -type INFO
 }Catch{
     LogIt -message ("Failed to delete files in the archive folder of 180 days older or more") -component "SFTP_Connection:161" -type ERROR
 }
