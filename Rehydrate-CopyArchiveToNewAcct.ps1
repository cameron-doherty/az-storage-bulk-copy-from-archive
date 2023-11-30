<#
.Synopsis
    Copy ARCHIVED Block Blob data in a designated source storage account to the target storage account
.DESCRIPTION

.EXAMPLE
    copyArchiveToNewAccount.ps1 -rgName <value> -srcAccount <value> -srcContainer <value> -destAccount <value> -destContainer <value> -batchSize <value>
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
    batchSize
        Number of items to return for each batch from the entire population of files in the srcContainer.  In other words, if
        the container has 1000 files, setting a batchSize of 250 will require the do-while loop to run through 4 times.  This 
        can help manage the number of items to process as running a single monolithic Get-AzStorageBlob that has a large number
        of files can take quite a bit of memory and processing time. Consider using the script which utilizes a CSV as the input
        to process rehydrating files
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

# Initialize these variables with your values.
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
    [int]$batchSize
)

$loginCheck = Get-AzContext

if (!$loginCheck) { Connect-AzAccount }

# Get the destination account context
$destCtx = (Get-AzStorageAccount -ResourceGroupName $rgName -Name $destAccount).Context

# Get the source account context
$srcCtx = (Get-AzStorageAccount -ResourceGroupName $rgName -Name $srcAccount).Context

$blobCount = 0
$Token = $Null

do {
    try {
        $Blobs = Get-AzStorageBlob -Context $srcCtx -Container $srcContainer -MaxCount $batchSize -ContinuationToken $Token
    }
    catch {
        Write-Host " ------------ ERROR ------------ " -ForegroundColor Red
        Write-Host $_
        continue
    }
    
    
    if($Blobs -eq $Null) { break }
    
    if($Blobs.GetType().Name -eq "AzureStorageBlob")
    {
        $Token = $Null
    }
    else
    {
        $Token = $Blobs[$Blobs.Count - 1].ContinuationToken;
    }
    
    $Blobs | ForEach-Object {
            if(($_.BlobType -eq "BlockBlob") -and ($_.AccessTier -eq "Archive") ) {
                $sourceBlobName = $_.Name
                $destinationBlobName = "$srcContainer/$sourceBlobName"

                Write-Host "PROCESSING " -ForegroundColor Cyan -NoNewLine
                Write-Host "$destinationBlobName :: " -NoNewLine
                $targetBlob = Get-AzStorageBlob -Context $destCtx -Container $destContainer -Blob $destinationBlobName -ErrorAction SilentlyContinue

                if($targetBlob -eq $null) {
                    Write-Host "REHYDRATING" -ForegroundColor Green
                    Start-AzStorageBlobCopy -SrcContainer $srcContainer -SrcBlob $sourceBlobName -Context $srcCtx -DestContainer $destContainer -DestBlob $destinationBlobName -DestContext $destCtx -StandardBlobTier Hot -RehydratePriority Standard -Confirm:$false | Out-Null
                }
                else
                {
                    Write-Host "SKIPPED" -ForegroundColor Yellow 
                }
                
        }
    }

    Write-Host "::: NEXT BATCH :::" -ForegroundColor Magenta
}
While ($Token -ne $Null)
