param (
    # Parameter help description
    [Parameter(Mandatory=$true)]
    [string]
    $Path
)

# Import Source CSV File
$sourceCSV = Import-CSV -Path $Path

# Set Variables
$maxRows = 2500 # Sets the max number of rows PER file. 
$startrow = 0 # Used as a checkpoint to determine the starting position of each split file
$counter = 1 # Simple placeholder for filename
$totalRows = $sourceCSV.Count # Evaluates what the total rows are in the CSV to prevent error in loop

# setting the while loop to continue as long as the value of the $startrow variable is smaller than the number of rows in your source CSV file
while ($startrow -le $totalRows) {
    # import of however many rows you want the resulting CSV to contain starting from the $startrow position and export of the imported content to a new file
    $sourceCSV | Select-object -skip $startrow -first $maxRows | Export-CSV "$($counter).csv" -NoClobber

    # advancing the number of the row from which the export starts
    $startrow += $maxRows

    # incrementing the $counter variable for next file
    $counter++
}
