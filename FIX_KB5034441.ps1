<#
.SYNOPSIS
    PowerShell script to apply the winRE security KB5034441 fix on Windows 10 22h2.

.DESCRIPTION
    This script fully automates the process of applying the KB5034441 fix on a Windows system instead of manually passing on each domain computers.
    
    The KB5034441 fix addresses specific issues as documented by Microsoft :

    IMPORTANT
    This update requires 250 MB of free space in the recovery partition to install successfully. If the recovery partition does not have sufficient free space, this update will fail.      In this case, you will receive the following error message: 

    0x80070643 - ERROR_INSTALL_FAILURE 

    To avoid this error or recover from this failure, please follow theâ€¯Instructions to manually resize your partition to install the WinRE update and then try installing this update.
    Or, to use a sample script to increase the size of the WinRE recovery partition, see Extend the Windows RE Partition.
    
.PARAMETER N/A
    There's no need for any parameter in this fully automated script.

.EXAMPLE
    PS C:\> .\FIX-KB5034441.ps1
    Applies the KB5034441 fix locally.

.NOTES
    File Name      : FIX-KB5034441.ps1
    Author         : Jessen Ranellucci
    Prerequisite   : PowerShell v3.0
    Copyright 2024 - WeSignit Inc.

    This script is provided as-is. Test it in a non-production environment first.
    You must obtain explicit permissions from the author before using this content if you are not affiliated with Wesignit company.

    For more information about KB5034441, refer to the Microsoft support documentation.

#>
# Validate if patch is already applyed
if ((get-hotfix -id KB5034441 -ErrorAction SilentlyContinue)) {write-host "Patch is already installed. Quitting now...";exit} else {
Write-host "The security patch 'KB5034441' is not installed on this system."
# Check if the build number matches the expected build
if ([System.Environment]::OSVersion.Version.build -eq "19045") {
write-host "Applying the fix now..."
# Step 3: Disable WinRE if it's not already disabled
$winreStatus = reagentc /info
if (!($winreStatus -like "*Disabled*")) {reagentc /disable}

# Step 2: Shrink OS partition
$osDisk = Get-Disk | Where-Object { $_.OperationalStatus -eq "Online" }
$osPartition = $osDisk | Get-Partition | Where-Object { $_.Type -eq "Basic" }
$recoveryPartition = Get-Partition -DiskNumber $osDisk.Number | Where-Object { $_.Type -eq "Recovery" }
# Define the diskpart
$disk = $osDisk.Number

# Check if partition is already extended
if ($recoveryPartition.size[0] -lt 569376769) {
#Check if partition is at expected schema
if (($recoveryPartition.PartitionNumber -lt $osPartition.PartitionNumber)) {
Write-host "Processing with unexpected schema"
#Calculate the reseize 
$shrinkSizeMB = 250
$shrinkSizeBytes = $shrinkSizeMB * 1MB  # Convert to bytes
$shrinkSizeBytes = $recoveryPartition.size[0] + $shrinkSizeBytes
$currentSizeBytes = $osPartition.Size[0] } 
else {
Write-host "Processing with standard schema"
#Processing with the standard expected recovery schema
$shrinkSizeMB = 250
$shrinkSizeBytes = $shrinkSizeMB * 1MB  # Convert to bytes
$currentSizeBytes = $osPartition.Size[0]
}
# Calculate the new size in bytes
$newSizeBytes = $currentSizeBytes - $shrinkSizeBytes
#check free space bytes on $osPartition and if at least $newSizeBytes is free proceed 
$freeSpaceBytes = (Get-CimInstance -ClassName Win32_LogicalDisk).FreeSpace
if (!($freeSpaceBytes -gt $shrinkSizeBytes)) {write "Error there's not enough available space on the disk to process the fix on that system. Quitting now...";reagentc /enable; exit}
# Resize the partition
Resize-Partition -InputObject $osPartition -Size $newSizeBytes

# Step 4: Identify the initial Recovery partition by type and delete it
$recoveryPartition | Remove-Partition -Confirm:$false

# Waiting on completition
start-sleep 5;

# Step 5: Create new recovery partition with increased size and custom label
# Check if the disk is GPT or MBR
if ($osDisk.partitionstyle -eq "GPT") {
# Disk is GPT, create a partition with specific attributes 
$Diskpart_RecoveryPart = @"
sel disk $disk
create partition primary id=de94bba4-06d1-4d40-a16a-bfd50179d6ac
gpt attributes=0x8000000000000001
format fs=ntfs label=`"Recovery`" quick
"@
$Diskpart_RecoveryPart | Out-File .\Diskpart_RecoveryPart.txt -Encoding ascii 
diskpart /s .\Diskpart_RecoveryPart.txt 

} 
else {
$Diskpart_RecoveryPart = @"
sel disk $disk
create partition primary id=27
format fs=ntfs label=`"Recovery`" quick
"@
$Diskpart_RecoveryPart | Out-File .\Diskpart_RecoveryPart.txt -Encoding ascii 
diskpart /s .\Diskpart_RecoveryPart.txt
    }
} 
else {write-host "INFO:Fix seem to have already been executed on this system. You may need to reboot the system before trying to apply the security patch again."
# Step 6: Re-enable WinRE
reagentc /enable
exit
}

#Removing the Diskpart script
Remove-Item .\Diskpart_RecoveryPart.txt -Force -ErrorAction SilentlyContinue
# Step 6: Re-enable WinRE
reagentc /enable
$winreStatus = reagentc /info
if (!($winreStatus -like "*Disabled*")) {write-host "WinRE has been successfully re-enabled"}
}
else {write-host "INFO:The OS system version is not compatible with this FIX.";EXIT}
}
write-host "All operations has been executed. If the security patch 'KB5034441' is still not installing properly, please reboot this system prior retrying."
exit