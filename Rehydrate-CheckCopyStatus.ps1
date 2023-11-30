<#
    DISCLAIMER: This code and information are provided "AS IS" without warranty of any kind, either
    expressed or implied. The entire risk arising out of the use or performance of the
    script and documentation remains with you. Furthermore, the author and any contributors
    shall not be liable for any damages you may sustain by using this information,
    whether direct, indirect, special, incidental or consequential, including, without
    limitation, damages for loss of business profits, business interruption, loss of business
    information or other pecuniary loss even if it has been advised of the possibility of
    such damages. 
#>

$rgName = "<resourceGroupName>"
$destAccount = "<destinationStorageAccountName>"
$destContainer = "<targetContainerName>" 

$ctx = (Get-AzStorageAccount -ResourceGroupName $rgName -Name $destAccount).Context

$blobCount = 0
$Token = $Null
$MaxReturn = 5000
$successCount = 0
$waitingCount = 0

do {
    $Blobs = Get-AzStorageBlob -Context $ctx -Container $destContainer -MaxCount $MaxReturn -ContinuationToken $Token
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
        $state = Get-AzStorageBlobCopyState -Blob $_.Name -Container $destContainer -Context $ctx
        if($state.Status -eq "Success") { $successCount += 1 } else { $waitingCount += 1 }
    }
}
While ($Token -ne $Null)

Write-Host "Number of Blobs Copied Successfully :: $successCount"
Write-Host "Number of Blobs Still Being Copied  :: $waitingCount"
