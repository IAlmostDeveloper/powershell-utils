# Скрипт для бэкапа указанных папок

$Destination = "D:\_Backup"
$Versions = "2"
$Backupdirs = "C:\Users\developer\Desktop", "D:\projects"
$ExcludeDirs = ($env:SystemDrive + "\Users\.*\AppData\Local"), "C:\Program Files (x86)\"
$logPath = "D:\_Backup"
$LogfileName = "Log"
$LoggingLevel = "3" #LoggingLevel only for Output in Powershell Window, 1=smart, 3=Heavy
$Zip = $true
Add-Type -AssemblyName "System.IO.Compression.FileSystem";

function Log-To-File {
    [CmdletBinding()]
    param
    (
        [ValidateSet('DEBUG', 'INFO', 'WARNING', 'ERROR')]
        [string]$Type,
        [string]$Text
    )
       
    # Set logging path
    if (!(Test-Path -Path $logPath)) {
        try {
            $null = New-Item -Path $logPath -ItemType Directory
            Write-Verbose ("Path: ""{0}"" was created." -f $logPath)
        }
        catch {
            Write-Verbose ("Path: ""{0}"" couldn't be created." -f $logPath)
        }
    }
    else {
        Write-Verbose ("Path: ""{0}"" already exists." -f $logPath)
    }
    [string]$logFile = '{0}\{1}_{2}.log' -f $logPath, $(Get-Date -Format 'yyyyMMdd'), $LogfileName
    $logEntry = '{0}: <{1}> <{2}> {3}' -f $(Get-Date -Format dd.MM.yyyy-HH:mm:ss), $Type, $PID, $Text
    
    try { Add-Content -Path $logFile -Value $logEntry }
    catch {
        Start-sleep -Milliseconds 50
        Add-Content -Path $logFile -Value $logEntry
    }
    if ($LoggingLevel -eq "3") { Write-Host $Text }
}

$FinalBackupdirs = @()
$BackupDestination = $Destination + "\Backup-" + (Get-Date -format yyyy-MM-dd-HH-mm-ss);
New-Item -Path $BackupDestination -ItemType Directory | Out-Null

foreach ($Dir in $Backupdirs) {
    if ((Test-Path $Dir)) {
        Log-To-File -Type INFO -Text "$Dir is fine"
        $FinalBackupdirs += $Dir
    }
    else {
        Log-To-File -Type WARNING -Text "$Dir does not exist and was removed from Backup"
    }
}

try {
    Log-To-File -Type INFO -Text "Calculate Size and check Files"
    $BackupDirFiles = @{ }
    $Files = @()
    $SumMB = 0
    $SumItems = 0
    $SumCount = 0
    $colItems = 0
    $ExcludeString = ""
    foreach ($Entry in $ExcludeDirs) {
        #Exclude the directory itself
        $Temp = "^" + $Entry.Replace("\", "\\").Replace("(", "\(").Replace(")", "\)") + "$"

        #$Temp = $Entry
        $ExcludeString += $Temp + "|"

        #Exclude the directory's children
        $Temp = "^" + $Entry.Replace("\", "\\").Replace("(", "\(").Replace(")", "\)") + "\\.*"

        #$Temp = $Entry
        $ExcludeString += $Temp + "|"
    }
    $ExcludeString = $ExcludeString.Substring(0, $ExcludeString.Length - 1)
    [RegEx]$exclude = $ExcludeString
    
    foreach ($Backup in $FinalBackupdirs) {

        $Files = Get-ChildItem -LiteralPath $Backup -recurse -Attributes D+!ReparsePoint, D+H+!ReparsePoint -ErrorVariable +errItems -ErrorAction SilentlyContinue | 
        ForEach-Object -Process { Add-Member -InputObject $_ -NotePropertyName "ParentFullName" -NotePropertyValue ($_.FullName.Substring(0, $_.FullName.LastIndexOf("\" + $_.Name))) -PassThru -ErrorAction SilentlyContinue } |
        Where-Object { $_.FullName -notmatch $exclude -and $_.ParentFullName -notmatch $exclude } |
        Get-ChildItem -Attributes !D -ErrorVariable +errItems -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -notmatch $exclude }

        $Files+= Get-ChildItem -LiteralPath $Backup  | 
        ForEach-Object -Process { Add-Member -InputObject $_ -NotePropertyName "ParentFullName" -NotePropertyValue ($_.FullName.Substring(0, $_.FullName.LastIndexOf("\" + $_.Name))) -PassThru -ErrorAction SilentlyContinue } |
        Get-ChildItem -Attributes !D -ErrorVariable +errItems -ErrorAction SilentlyContinue
        $BackupDirFiles.Add($Backup, $Files)


        $colItems = ($Files | Measure-Object -property length -sum) 
        $Items = 0
        
        if ($colItems.Sum -ne $null){
            $SumMB += $colItems.Sum.ToString()
        }
        $SumItems += $colItems.Count
    }

    $TotalMB = "{0:N2}" -f ($SumMB / 1MB) + " MB of Files"
    Log-To-File -Type INFO -Text "There are $SumItems Files with  $TotalMB to copy"

    #Log any errors from above from building the list of files to backup.
    [System.Management.Automation.ErrorRecord]$errItem = $null
    foreach ($errItem in $errItems) {
        Log-To-File -Type WARNING -Text ("Skipping `"" + $errItem.TargetObject + "`" Error: " + $errItem.CategoryInfo)
    }
    Remove-Variable errItem
    Remove-Variable errItems

    try {
        foreach ($Backup in $FinalBackupdirs) {
            $Index = $Backup.LastIndexOf("\")
            $SplitBackup = $Backup.substring(0, $Index)
            $Files = $BackupDirFiles[$Backup]
    
            foreach ($File in $Files) {
                $restpath = $file.fullname.replace($SplitBackup, "")
                try {
                    # Use New-Item to create the destination directory if it doesn't yet exist. Then copy the file.
                    New-Item -Path (Split-Path -Path $($BackupDestination + $restpath) -Parent) -ItemType "directory" -Force -ErrorAction SilentlyContinue | Out-Null
                    Copy-Item -LiteralPath $file.fullname $($BackupDestination + $restpath) -Force -ErrorAction SilentlyContinue | Out-Null
                    Log-To-File -Type Info -Text $("'" + $File.FullName + "' was copied")
                }
                catch {
                    $ErrorCount++
                    Log-To-File -Type Error -Text $("'" + $File.FullName + "' returned an error and was not copied")
                }
                $Items += (Get-item -LiteralPath $file.fullname).Length
                $Index = [array]::IndexOf($BackupDirs, $Backup) + 1
                $Text = "Copy data Location {0} of {1}" -f $Index , $BackupDirs.Count
                if ($File.Attributes -ne "Directory") { $count++ }
            }
        }
        $SumCount += $Count
        $SumTotalMB = "{0:N2}" -f ($Items / 1MB) + " MB of Files"
        Log-To-File -Type Info -Text "----------------------"
        Log-To-File -Type Info -Text "Copied $SumCount files with $SumTotalMB"
        if ($ErrorCount ) { Log-To-File -Type Info -Text "$ErrorCount Files could not be copied" }

    }
    catch {
        throw;
    }
}
catch {
    throw;
}

if ($Zip) {     
    try {
        [IO.Compression.ZipFile]::CreateFromDirectory($BackupDestination, "$BackupDestination.zip");       
        Remove-Item $BackupDestination -Force -Recurse
    }
    catch {
        throw;
    }
}

$count = (Get-ChildItem $Destination | Where-Object { $_.Attributes -eq "Directory" }).count
if ($count -gt $Versions) {
    Log-To-File -Type Info -Text "Found $count Backups"
    $Folder = Get-ChildItem $Destination | Where-Object { $_.Attributes -eq "Directory" } | Sort-Object -Property CreationTime -Descending:$false | Select-Object -First 1

    Log-To-File -Type Info -Text "Remove Dir: $Folder"
    
    $Folder.FullName | Remove-Item -Recurse -Force 
}

$CountZip = (Get-ChildItem $Destination | Where-Object { $_.Attributes -eq "Archive" -and $_.Extension -eq ".zip" }).count
Log-To-File -Type Info -Text "Check if there are more than $Versions Zip in the Backupdir"

if ($CountZip -gt $Versions) {
    $Zip = Get-ChildItem $Destination | Where-Object { $_.Attributes -eq "Archive" -and $_.Extension -eq ".zip" } | Sort-Object -Property CreationTime -Descending:$false | Select-Object -First 1
    Log-To-File -Type Info -Text "Remove Zip: $Zip"
    $Zip.FullName | Remove-Item -Recurse -Force 
}