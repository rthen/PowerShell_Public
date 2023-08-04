<#
	Script that checks if device has supported TPM, and if so, enables BitLocker. 
  If BitLocker is enabled, it will sync key up to Azure AD. This script is meant to be executed in Intune as a remediation script.
#>
$ErrorActionPreference = "Stop"

$manage_bde_status = C:\Windows\System32\manage-bde.exe -status C:
$volume = Get-BitLockerVolume -MountPoint "C:" | Select-Object *

if ($volume){
        if ($manage_bde_status -match "Restart the computer to run a hardware test"){
            Write-Host "BitLocker waiting for a reboot to carry out hardware test before encrypting drive. Enabling BitLocker will be skipped. However, key(s) should be backed up to Azure AD/Intune."
            exit 0
        }else{
            try{
                # Double check that BitLocker isn't on for the C: drive
                if (($volume.ProtectionStatus -eq "Off") -and ($volume.VolumeStatus -eq "FullyDecrypted")){
                    $TPM = Get-TPM
                    $WMITPMInfo = Get-WmiObject -Namespace "root\cimv2\security\microsofttpm" -Query "Select * from win32_tpm"
                    $TPMVersion = $WMITPMInfo.PhysicalPresenceVersionInfo
    
                    # Verify that there is TPM module and that it is properly configured, as well as verify that it is at least version 1.2
                    if ( (($TPM.TpmPresent -eq $True) -and ($TPM.TpmReady -eq $True) -and ($TPM.TpmEnabled -eq $True)) -or (($WMITPMInfo.IsActivated_InitialValue -eq $True) -and ($WMITPMInfo.IsEnabled_InitialValue -eq $True)) ){
                        if ($TPMVersion -ge 1.2){
                            Enable-BitLocker -MountPoint "C:" -EncryptionMethod XtsAes128 -RecoveryPasswordProtector
                            
                            # Need to re-query volume info to properly grab the KeyProtectorID once encryption has been initiated
                            $volumeAfterEncryption = Get-BitLockerVolume -MountPoint "C:" | Select-Object *
                            $KeyProtector = $volumeAfterEncryption.KeyProtector
                            $KeyProtectorIDs = @(($KeyProtector | Where-Object {$_.KeyProtectorType -eq "RecoveryPassword"}).KeyProtectorID) # Retrieve the KeyProtectorID for the recovery password
                            
                            foreach ($KeyProtectorID in $KeyProtectorIDs){
                                BackupToAAD-BitLockerKeyProtector -MountPoint "C:" -KeyProtectorId $KeyProtectorID # Sync key to Azure AD
                            }
                            Write-Host "Request to enable BitLocker succeeded, and key(s) has been successfully backed up for the C: drive to Azure AD. KeyProtectorID(s)=$KeyProtectorID"
                            exit 0
                        }else{
                            Write-Host "TPM version not greater or equals to 1.2, BitLocker will not be enabled. Current TPM version: $TPMVersion"
                            exit 1
                        }
                    }else{
                        if ($TPM.TpmPresent -eq $False){
                            Write-Host "Get-TPM: TPM not present"
                        }elseif ($TPM.TpmReady -eq $False){
                            Write-Host "Get-TPM: TPM not ready"
                        }elseif ($TPM.Enabled -eq $False){
                            
                            Write-Host "Get-TPM: TPM not enabled"
                        }elseif ($WMITPMInfo.IsActivated_InitialValue -eq $False){
                            Write-Host "Get-WMIObject: TPM is not active"
                        }elseif ($WMITPMInfo.IsEnabled_InitialValue -eq $False){
                            Write-Host "Get-WMIObject: TPM is not enabled"
                        }
                        exit 1
                    }
                }elseif (($volume.ProtectionStatus -eq "Off") -and ($manage_bde_status -match "Used Space Only Encrypted")){
                    Write-Host "Skipping enabling BitLocker as the protection is off and disk encryption is set to 'Used Space Only Encrypted'. Please disable partial encryption."
                    exit 1
                }elseif (($volume.ProtectionStatus -eq "On") -and ($manage_bde_status -match "Fully Encrypted")){
                    Write-Host "Skipping enabling Bitlocker, protection status set to 'On' and conversion type set to 'Fully Encrypted'. Manage-BDE: $manage_bde_status"
                    exit 1
                }elseif (($volume.ProtectionStatus -eq "Off") -and ($volume.VolumeStatus -eq "DecryptionInProgress")){
                    Write-Host "Skipping enabling Bitlocker, decryption in progress (most likely the encryption was set to 'Used Space Only Encrypted' and the 'Check Bitlocker Conversion Status' script ran). Manage-BDE: $manage_bde_status"
                    exit 1
                }else{
                    Write-Host "Skipping enabling Bitlocker, unknown Bitlocker status. Manage-BDE: $manage_bde_status"
                    exit 1
                }
            }catch{
                $errMsg = $_.Exception.Message
                return "Error running script: $errMsg"
                exit 1
            }
        }
}else{
    Write-Host "Unable to find a C: drive that supports BitLocker"
    exit 1
}
