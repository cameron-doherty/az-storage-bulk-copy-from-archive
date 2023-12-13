<#
.Synopsis
    Copy ARCHIVED Block Blob data in a designated source storage account to the target storage account
.DESCRIPTION

.EXAMPLE
    copyArchiveToNewAccount.ps1 -rgName <value> -srcAccount <value> -srcContainer <value> -destAccount <value> -destContainer <value> -csvList <value>
.INPUTS
    rgName
        Resource Group Name of Storage Containers. Currently requires that source/destination accounts be within the same Resource Group and Azure Region
    srcAccount
        Name of the SOURCE blob storage account
    srcContainer
        Name of the SOURCE blob storage container
    destAccount
        Name of the DESTINATION blob storage account
    destContainer
        Name of the DESTINATION blob storage container
    csvDirectory
        This is the directory where the script will look for CSV files containing the list of blobs to process.  The script will iterate through each CSV file.  
    
        Each CSV file should be a formatted list of blobs from the srcContainer.  Currently the expected CSV contains the following columns at minimum:
            
            Name        :: Name of the blob including container name and any folder structure delimited by '/'. 
                        Ex: srcContainerName/RootFolder/SubFolder/File.txt
            AccessTier  :: Hot, Cool, Cold, Archive. As this script targets rehydrating Archive, this is
                        used to filter out non-Archive tiered blobs.
            BlobType    :: Type of blob (block, page, etc).  This is used to filter out non-block-blob objects
                        for copy

        For relatively small containers (<10k objects) its likely fine to use the Get-AzStorageBlob 
        command to just list out the blobs and then Export-CSV.  For containers with large number of 
        files it is recommended to use the Blob Inventory Service to generate the CSV for you automatically.
.OUTPUTS
    Script outputs a checkpoint every 500 files processed.  This is to help you track progress as the script runs.

.NOTES
    DISCLAIMER: This code and information are provided "AS IS" without warranty of any kind, either
    expressed or implied. The entire risk arising out of the use or performance of the
    script and documentation remains with you. Furthermore, the author and any contributors
    shall not be liable for any damages you may sustain by using this information,
    whether direct, indirect, special, incidental or consequential, including, without
    limitation, damages for loss of business profits, business interruption, loss of business
    information or other pecuniary loss even if it has been advised of the possibility of
    such damages. 
#>


[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$rgName,

    [Parameter(Mandatory=$true)]
    [string]$srcAccount,

    [Parameter(Mandatory=$true)]
    [string]$destAccount,

    [Parameter(Mandatory=$true)]
    [string]$srcContainer,

    [Parameter(Mandatory=$true)]
    [string]$destContainer,

    [Parameter(Mandatory=$true)]
    [string]$csvDirectory
)

$loginCheck = Get-AzContext

if (!$loginCheck) { 
    Write-Host "Please login before continuing!" -ForegroundColor Red
    exit 
}

# Get the destination account context
$destCtx = (Get-AzStorageAccount -ResourceGroupName $rgName -Name $destAccount).Context

# Get the source account context
$srcCtx = (Get-AzStorageAccount -ResourceGroupName $rgName -Name $srcAccount).Context

$totalProcessed = [hashtable]::Synchronized(@{})
$totalProcessed.counter = 0

Get-ChildItem -Path $csvDirectory -Filter *.csv | ForEach-Object {
    $csvList = $_.FullName
    $blobList = Import-Csv -Path $csvList | Where-Object {$_.AccessTier -eq "Hot" -and $_.BlobType -eq "BlockBlob"}
    $totalToBeProcessed = $blobList.Count
    
    Write-Host "$(Get-Date -Format u) :: Processing $($_.Name) containing $totalToBeProcessed files"

    $blobList | ForEach-Object -ThrottleLimit 10 -Parallel { 
        $targetBlob = Get-AzStorageBlob -Context $using:destCtx -Container $using:destContainer -Blob $_.Name -ErrorAction SilentlyContinue

        if($targetBlob -eq $null) {
            Start-AzStorageBlobCopy -SrcContainer $using:srcContainer -SrcBlob $_.Name.split('/',2)[1] -Context $using:srcCtx -DestContainer $using:destContainer -DestBlob $_.Name -DestContext $using:destCtx -StandardBlobTier Hot -Force -Confirm:$false | Out-Null
            #Write-Host "$(Get-Date -Format u) :: $($_.Name) :: REHYDRATED"
        }
        else {
            #Write-Host "$(Get-Date -Format u) :: $($_.Name) :: SKIPPED"
        }
        
        $totalProcessed = $using:totalProcessed
        $totalProcessed.counter++

        if($totalProcessed.counter % 500 -eq 0) {
            Write-Host "$(Get-Date -Format u) :: CHECKPOINT :: $($totalProcessed.counter) files processed from $using:csvList :: Last File = $($_.Name)" -Backgroundcolor Yellow -ForegroundColor Black
        }
    }
}

Write-Host "`n`n------------ SUMMARY ------------ " -ForegroundColor Magenta
Write-Host "$($totalProcessed.counter)" -NoNewLine -ForegroundColor Green
Write-Host " out of " -NoNewLine
Write-Host "$totalToBeProcessed" -NoNewLine -ForegroundColor Green
Write-Host " blobs processed."
