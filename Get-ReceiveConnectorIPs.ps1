<# 

.SYNOPSIS
    Script is intended to help determine servers that are using an Exchange server to connect and send email.
    
    This is especially pertinent in a decomission scenario, where the logs are to be checked to ensure that all SMTP traffic has been moved to the correct endpoint.

    Based on this script:
    https://blogs.technet.microsoft.com/rmilne/2019/01/25/checking-exchange-smtp-logs-to-determine-usage/

.DESCRIPTION

    Logs on an Exchange 2010 servers are here by default.
    C:\Program Files\Microsoft\Exchange Server\V14\TransportRoles\Logs\ProtocolLog\SmtpReceive

    Note that the script can be easily modified for other versions, or to look at the SMTPSend logs instead.  

    The script that this is based on reads in the log files as text documents and pulls out the 5th element in each line. This works, but 
    I found that working with the  data as a CSV was much faster in powershell. I remove the headers from the files which have no relevance
    for this purpose and keep the rest of the data.

    An empty array is declared that will be used to hold the data gathered during each iteration. 
    This allows for the additional information to be easily added on, and then either echo it to the screen or export to a CSV file

	# Sample Exchange 2010 SMTP Receive log

	#	#Software: Microsoft Exchange Server
	#	#Version: 14.0.0.0
	#	#Log-type: SMTP Receive Protocol Log
	#	#Date: 2019-01-25T00:03:58.478Z
	#	#Fields: date-time,connector-id,session-id,sequence-number,local-endpoint,remote-endpoint,event,data,context
	#	2019-01-25T00:03:58.478Z,TAIL-EXCH-1\Internet Mail,08D675E58CA1DA38,0,10.0.0.6:25,185.234.217.220:61061,+,,
	#	2019-01-25T00:03:58.494Z,TAIL-EXCH-1\Internet Mail,08D675E58CA1DA38,1,10.0.0.6:25,185.234.217.220:61061,*,SMTPSubmit SMTPAcceptAnySender SMTPAcceptAuthoritativeDomainSender AcceptRoutingHeaders,Set Session Permissions


.ASSUMPTIONS
    Logging was enabled to generate the required log files.
    Logging was enabled previously, and time was allowed to colled the data in the logs

    Not all activity will be present on a given server.  Will have to check multiple in most deployments.
    Not all activity will be present in the logs.  For example, Exchange maintains 30 days of logs by default.  This will not catch connections for processes which
    send email once a quarter or once a fiscal year.

    Assuption is that something will likely be negatively impacted.  Application owners should have been told to update their config, so we can say "unlucky" to them...

	You can add your error handling if you need it.  

.VERSION
  
	1.0  25-1-2019 -- Initial script released to the scripting gallery
#>

########################################
# Modify this info for your environment
#
# We will process all the files in this directory. This should be up to 30 days of logs if it's configured properly.
$LogFilePath = "C:\Program Files\Microsoft\Exchange Server\V14\TransportRoles\Logs\ProtocolLog\SmtpReceive\*.log"

# This is our working directory. The modified logs will go here. We will also output a file with the IP list here.
$outputPath = "C:\Scripts\Receive Connector Logs\"

# The filename to export
$outputFile = "RemoteIPs.csv"

# 
########################################
$LogFiles = Get-Item  $LogFilePath

# Count the log files for purposes of the status bar.
$Count = @($logfiles).count

# Counter for progress bar.
$int = 0 


# Clean up the headers of the CSV file.
# Remove the first 6 lines of the log file and append our own CSV header onto the file to make it easier to digest.
# Create copies of all the log files with headers that we can work with easier. Save these modified files in the output directory.
ForEach ($Log in $LogFiles) {
	# Write a progress bar to the screen so that we know how far along this is...
	# Increment the counter 
	$Int = $Int + 1
	# Work out the current percentage 
	$Percent = $Int/$Count * 100
	
	# Write the progress bar out with the necessary verbiage....
	Write-Progress -Activity "Cleaning Log Files" -Status "Processing log File $Int of $Count" -PercentComplete $Percent 

    Write-Host "Processing Log File  $Log" -ForegroundColor Magenta
	Write-Host
	$FileHeader = "datetime,connectorid,session,sequence,localip,remoteip,event,data,context"
	# Skip the first 6 lines of the file as they are headers we do not want to review
    $FileContent = Get-Content $Log | Select-Object -Skip 6
    $OutFilePath = $outputPath + $log.name 

    # Create a new file with the new header and the rest of the contents of the old log.
    add-content $outfilepath $FileHeader
    add-content $outfilepath $filecontent
}

# Import these new files and read their contents into a large array.
$files = get-childitem "$outputpath\*.log" | Select-Object Name

# The records array holds all the log entries that we'll be searching.
$records = @()

# Reset the counter for the next progress bar.
$int = 0

# Count the files in this directory.
$filecount = $files.count

# Read all of the logs in the directory into an array that will contain all log entries.
foreach($file in $files) {
    # Write a progress bar to the screen so that we know how far along this is...
	# Increment the counter 
	$Int = $Int + 1
	# Work out the current percentage 
	$Percent = $Int/$FileCount * 100
    Write-Progress -Activity "Reading Log FIles" -Status "Reading Log $Int of $fileCount" -PercentComplete $Percent 
    $records += import-csv $file.name
}

# Now we have all of the records from all of the log files in a single variable. Let's figure out how massive
# it is for progress bar purposes.
$Recordcount = $records.count
$int = 0

# In order to speed up the processing, we sort the records by remote IP address. 
# This process may take a long time depending on how busy the server is and has no progress bar.

write-output "Sorting records. This may take a while...."
$records = $records | Sort-Object RemoteIP

# to speed up the data collection we only need to  process each remote IP once.
# Since we've sorted all of the records we're dealing with by IP we know that all instances
# of the same IP will be consecutive in the $records variable.
# We keep track of the last remote IP we were looking at and 
# if the next log entry is the same IP, we skip it and move on.
$LastRemoteIP = $null

# Status bar counter reset.
$int = 0

# Results holds just the IP information that we need.
$results = @()

# Run through all the records from all the logs and record each unique IP address discovered there.
foreach ($record in $records) {
	# Write a handy dandy progress bar to the screen so that we know how far along this is...
    # Increment the counter 
    $Int = $Int + 1 

    # Only do any processing if we're working with an IP address we haven't seen yet.
    if ($LastRemoteIP - ne $record.RemoteIP) {

        # Work out the current percentage
        $Percent = $Int/$RecordCount * 100
        Write-Progress -Activity "Collecting record details" -Status "Processing record $Int of $recordCount" -PercentComplete $Percent 

        # Split the IPs up from the port number, because we don't care about what port was used.
        $remoteIP = $record.remoteip.Split(":")
        $remoteIP = $RemoteIP[0]
        $localport = $record.localip.split(":")
        $localport = $localport[1]

        $connector = New-object System.Object
        $connector | Add-member -type NoteProperty -Name RemoteIP -value $RemoteIP
        $connector | Add-Member -Type NoteProperty -name ConnectorName -value $record.connectorid
        $connector | Add-Member -type NoteProperty -name LocalPort -Value $localport
        $results += $connector
        $LastRemoteIP = $record.remoteIP
    }
    
}

$results = $results | Sort-Object RemoteIP -Unique
$results | Export-Csv $outputPath + $outputFile