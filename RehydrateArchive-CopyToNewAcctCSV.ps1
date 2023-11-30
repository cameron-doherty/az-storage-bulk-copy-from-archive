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
    csvList
        CSV formatted list of blobs from the srcContainer.  Currently the expected CSV contains the following columns at minimum:
            
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
    Script outputs the name of each source file from the csvList and reports back if it is processing a rehydration action or 
    if it is skipped because the blob already exists in the target storage account.

    PROCESSING source/Folder1/File1.txt :: REHYDRATING
    PROCESSING source/Folder1/SubFolder1/File1.txt :: SKIPPED
    PROCESSING source/RootFile.txt :: REHYDRATING

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
    [string]$csvList
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

$blobList = Import-Csv -Path $csvList
$totalToBeProcessed = $blobList.Count
$totalProcessed = 0 

$blobList | Where-Object {$_.AccessTier -eq "Archive" -and $_.BlobType -eq "BlockBlob"} | ForEach-Object { 
    Write-Host "PROCESSING " -ForegroundColor Cyan -NoNewLine
    Write-Host "$($_.Name) :: " -NoNewLine

    $targetBlob = Get-AzStorageBlob -Context $destCtx -Container $destContainer -Blob $_.Name -ErrorAction SilentlyContinue

    if($targetBlob -eq $null) {
        Write-Host "REHYDRATING" -ForegroundColor Green
        Start-AzStorageBlobCopy -SrcContainer $srcContainer -SrcBlob $_.Name.split('/',2)[1] -Context $srcCtx -DestContainer $destContainer -DestBlob $_.Name -DestContext $destCtx -StandardBlobTier Hot -RehydratePriority Standard -Confirm:$false | Out-Null
    }
    else
    {
        Write-Host "SKIPPED" -ForegroundColor Yellow 
    }

    $totalProcessed++
}

Write-Host "`n`n------------ SUMMARY ------------ " -ForegroundColor Magenta
Write-Host "$totalProcessed" -NoNewLine -ForegroundColor Green
Write-Host " out of " -NoNewLine
Write-Host "$totalToBeProcessed" -NoNewLine -ForegroundColor Green
Write-Host " blobs processed."
