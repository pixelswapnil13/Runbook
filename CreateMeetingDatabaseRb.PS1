#WebhookURL: "https://a046ed9d-d7be-4c6d-b967-061ab85b5b59.webhook.ae.azure-automation.net/webhooks?token=6ApiZoHlA%2bTGzF2vwwE1pHEvY0tEG0Gfvm%2fMvgvf8pk%3d",
#Payload:{
# ResourceGroup = auedvzagmrsg002,
# StorageAccountName = aueagmstadv003,
# StorageAccountKey = "AmT1/7/lRAkAnGTWkre7IKAhvr+3mwdsgi5U2xTjhgXibRHRyrCPKy0wNwn5L11G4q6kEdJ9H8/q+ASt3enfCA==",
# LoaderContainerName = "agmloader",
# BaseFolderName: "LinkMeet",
# AzureDbServerName = "aueagmsqldv002",
# Edition =""  (set Hypserscale only for prod)
# ComputeModel= ""  (set serverless only for prod)
# RequestedServiceObjectiveName = ""  (set HS_S_Gen5_4 only for prod)
# FailoverGroupName = ""  (prod failover group name)
# AzureSqlServerUserId = _azureSqlServerUserId,  #
# AzureSqlServerPassword = _azureSqlServerPassword,
# MeetingId="MPXEPS202301",
# MeetingYear = "2024",
# MeetingFileName="AGM_extract_MPXEPS202301.tar.gz-09-12-37_13-03-2023",
# MeetingType="STD",
# IdUsed="SRN",
# MasterDbName = "AGM_Clone_Master",
# ProdClientDbName="AGM_MPXEPS202301_20240209_Prod",
# DemoClientDbName="AGM_MPXEPS202301_20240209_Demo"
# }
param
(
    [Parameter(Mandatory=$false)]
    [object] $WebhookData
)
try {
        write-output  "Logging in to Azure..."
        $AzureContext = (Connect-AzAccount -Identity)
        Write-Output "AzureContext:" $AzureContext ;
        Write-Output "connected successfully.";
        write-output "Runbook Job ID: " $PSPrivateMetadata.JobId.Guid
        $createMeetingRbJobId=$PSPrivateMetadata.JobId.Guid
        write-output "WebhookData-" $WebhookData
        $params = (ConvertFrom-Json -InputObject $WebhookData.RequestBody)
  
        write-output "WebHook Payload:" $params
       
        $resourceGroupName =$params.ResourceGroup 
        $storageAccountName =$params.StorageAccountName            
        $storageAccountKey =  $params.StorageAccountKey 
        $loaderContainerName = $params.LoaderContainerName                  
        $azureDbServerName =$params.AzureDbServerName
        $secondaryDbServerName = $params.AzureSecondaryDbServerName 
        $azureSqlServerUserId =$params.AzureSqlServerUserId
        $azureSqlServerPassword =$params.AzureSqlServerPassword            
        $meetingId=$params.MeetingId
        $meetingYear=$params.MeetingYear
        $meetingFileName=$params.MeetingFileName       
        $meetingType=$params.MeetingType
        $idUsed=$params.IdUsed
        $masterDbName=$params.MasterDbName      
        $prodClientDbName=$params.ProdClientDbName        
        $demoClientDbName=$params.DemoClientDbName
        $baseFolderName= $params.BaseFolderName
        $edition =  $params.Edition  
        $computeModel= $params.ComputeModel  
        $requestedServiceObjectiveName = $params.RequestedServiceObjectiveName  
        $failoverGroupName = $params.FailoverGroupName
        $secondaryResourceGroup =$params.AzureSecondaryResourceGroup 
        $configurationDbName= $params.ConfigurationDbName  
 
        $blobStorageEndpoint = "https://$storageAccountName.blob.core.windows.net/"
        write-output "blobStorageEndpoint:" $blobStorageEndpoint 
        $filpath = "$blobStorageEndpoint$loaderContainerName/$baseFolderName/$meetingYear/$meetingId/Extract"  
        write-output "filpath:" $filpath
        $tier = "Hot"
        $LogFull = "sourcefile" 
        $LogItem = New-Item -ItemType Directory -Name $LogFull
        $resultLogFull = "result" 
        $resultLogItem = New-Item -ItemType Directory -Name $resultLogFull
 
        # azure Conext
        $azStorageContext = New-AzStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey -BlobEndpoint $blobStorageEndpoint
       
        #Fetching file and downloading into sourcefile folder.  
        $fileName=Get-AzStorageBlob -Context $azStorageContext -Container  $loaderContainerName -Blob "$baseFolderName/$meetingYear/$meetingId/$meetingFileName"
        $fileName = $fileName.Name
        write-output "MeetingTarFileName:" $fileName
        $filedownload = Get-AzStorageBlobContent -Container $loaderContainerName -Blob $fileName -Destination $logfull -Context $azStorageContext
        write-output "filedownload":$filedownload
        Write-Output "Download complete." 
       
        #deflate zip file
        $sourcepath = $logfull + "\" + $fileName
 
        #Unzipping
        write-output "Unzipping meeting Tar file."
        tar -xzf $sourcepath -C $resultLogFull
        write-output "Completed unzipping meeting Tar file."
 
        #Uploading unzipped files into blob.
        write-output "Uploading extracted meeting files."
        Get-ChildItem -Path $resultLogFull -Recurse | foreach-object {
        $sourceFilePath = $resultLogFull + "/" + $_.Name
        $destblob = "$baseFolderName/"+$meetingYear +"/" + $meetingId + "/Extract/" + $_.Name 
        write-output "destblob:" $destblob
        Set-AzStorageBlobContent -Container $loaderContainerName -Blob $destblob -Context $azStorageContext -File $sourceFilePath -StandardBlobTier Hot -Force
        }
        write-output "Completed uploading of extracted meeting files."
       
       
        #Start - DB Cloning
        if($prodClientDbName){
        write-output "Start to create Prod database."
        New-AzSqlDatabaseCopy -ResourceGroupName $resourceGroupName -ServerName $azureDbServerName -DatabaseName $masterDbName -CopyResourceGroupName $resourceGroupName -CopyServerName $azureDbServerName -CopyDatabaseName $prodClientDbName
        write-output "Completed Database cloning and $prodClientDbName database is ready."
 
        #Set Configuration- Database size as Hyperscale
        if($edition -and $computeModel -and $requestedServiceObjectiveName)
        {
        write-output "Start to set Databse as Hyperscale."
        Set-AzSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $azureDbServerName `
         -DatabaseName $prodClientDbName -Edition $edition -ComputeModel $computeModel `
         -RequestedServiceObjectiveName $requestedServiceObjectiveName
        write-output "End of setting Databse as Hyperscale."
        }
        
        #Start - Bulk insert 
        $prodDatabaseConnection = New-Object System.Data.SqlClient.SqlConnection
        $prodDatabaseConnection.ConnectionString = "Data Source=$azureDbServerName.database.windows.net;Initial Catalog=$prodClientDbName;Integrated Security=False;User ID=$azureSqlServerUserId;Password=$azureSqlServerPassword;Connect Timeout=60;Encrypt=False;TrustServerCertificate=False"
        $prodDatabaseConnection.Open()
        Write-Output "Connection OPEN"
 
        write-output "Start bulk insert into prod database."
        Write-Output "Databse command text:sp_InsertDataFromStorageFiles."
    
        # Create command
        $prodDatabaseCommand = New-Object System.Data.SqlClient.SqlCommand
        $prodDatabaseCommand.Connection = $prodDatabaseConnection  
        Write-Output "EXEC sp_InsertDataFromStorageFiles '$meetingId', '$meetingType', '$idUsed', '$filpath','$azureSqlServerUserId','password'"
        $prodDatabaseCommand.CommandText = "EXEC sp_InsertDataFromStorageFiles '$meetingId', '$meetingType', '$idUsed', '$filpath','$azureSqlServerUserId','$azureSqlServerPassword'"
        Write-Output "Executing query on prod database."
        $prodDatabaseCommand.CommandTimeout = 600
        $prodDatabaseCommand.ExecuteNonQuery()
        $prodDatabaseConnection.Close()
        Write-output "Connection closed."
        write-output "Completed bulk insert into prod database."    
 
             
        if($failoverGroupName)
        {
        Write-output "Adding the database to the failover group..." 
        $failoverGroup = Get-AzSqlDatabase -ResourceGroupName $resourceGroupName `
                                           -ServerName $azureDbServerName `
                                            -DatabaseName $prodClientDbName | `
                         Add-AzSqlDatabaseToFailoverGroup -ResourceGroupName $resourceGroupName `
                                 -ServerName $azureDbServerName `
                                 -FailoverGroupName $failoverGroupName
        write-output "Failover group:" $failoverGroup  
        Write-output "Successfully added the database to the failover group..."
        }                    
        }
        
        if($demoClientDbName){
        write-output "Start to create  Demo database."
        New-AzSqlDatabaseCopy -ResourceGroupName $resourceGroupName -ServerName $azureDbServerName -DatabaseName $prodClientDbName -CopyResourceGroupName $resourceGroupName -CopyServerName $azureDbServerName -CopyDatabaseName $demoClientDbName
        write-output "Completed Database cloning and $demoClientDbName database is ready."
        }
        #End - DB Cloning
 
        # Delete extracted meeting files from Extract folder.
        write-output "Start deleting extracted meeting files."  
        $extractFoldePath="$baseFolderName/"+ $meetingYear + "/" + $meetingId + "/Extract/*.out"
        
        Get-AzStorageBlob -Container $loaderContainerName -Blob $extractFoldePath -Context $azStorageContext | Remove-AzStorageBlob
        write-output "Completed deleting of extracted meeting output files."
       
        #Connection for for agm configuration database.
        $agmConfigDatabaseConnection = New-Object System.Data.SqlClient.SqlConnection
        $agmConfigDatabaseConnection.ConnectionString = "Data Source=$azureDbServerName.database.windows.net;Initial Catalog=$configurationDbName;Integrated Security=False;User ID=$azureSqlServerUserId;Password=$azureSqlServerPassword;Connect Timeout=60;Encrypt=False;TrustServerCertificate=False"
        $agmConfigDatabaseConnection.Open()
        Write-Output "Connection OPEN for agm config"
 
        # Create command for agm master table  to update status.
        $agmConfigDatabaseCommand = New-Object System.Data.SqlClient.SqlCommand
        $agmConfigDatabaseCommand.Connection = $agmConfigDatabaseConnection   
        Write-Output "EXEC SP_UpdateAgmMasterAfterCreateMeeting '$createMeetingRbJobId',true"
        $agmConfigDatabaseCommand.CommandText = "EXEC SP_UpdateAgmMasterAfterCreateMeeting '$createMeetingRbJobId',true"
        Write-Output "Executing query on agm master database."
        $agmConfigDatabaseCommand.ExecuteNonQuery()
        $agmConfigDatabaseConnection.Close()
        Write-Output "Connection closed for agm config db."
        write-output "Completed status update in agm master table."
 }
catch{
    Write-Error -Message $_.Exception
    $errorDesc = $_.Exception -replace "'","''"
    
        # Write-Output "There is no system-assigned user identity. Aborting."; 
        # exit
        write-output "Exception occured while executing runbook."
        write-output "Start rollback."
 
        # delete database from failover group.
        if($secondaryDbServerName)
        {
        Write-Output "Delete  $databaseName  database from secondary server of failover group."
        Remove-AzSqlDatabase -ResourceGroupName $secondaryResourceGroup -ServerName $secondaryDbServerName -DatabaseName $prodClientDbName                      
        write-output " $databaseName deleted succesfully from secondary server of failover group." 
        }
 
        if($prodClientDbName){
        Write-Output "Delete prod Database."
        Remove-AzSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $azureDbServerName -DatabaseName $prodClientDbName
        write-output $prodClientDbName "deleted succesfully."
        }
 
       
 
        if($demoClientDbName){
        Write-Output "Delete Demo Database."
        Remove-AzSqlDatabase -ResourceGroupName $resourceGroupName -ServerName $azureDbServerName -DatabaseName $demoClientDbName
        write-output $demoClientDbName "deleted succesfully."
        }
 
        # Delete extracted meeting files from Extract folder.
        write-output "Start deleting extracted meeting files."
        $extractFoldePath="$baseFolderName/"+ $meetingYear + "/" + $meetingId + "/Extract/*.out"
        Get-AzStorageBlob -Container $loaderContainerName -Blob $extractFoldePath -Context $azStorageContext | Remove-AzStorageBlob
        write-output "Completed deleting of extracted meeting output files."
 
 
        #Connection for for agm configuration database.
        $agmConfigDatabaseConnection1 = New-Object System.Data.SqlClient.SqlConnection
        $agmConfigDatabaseConnection1.ConnectionString = "Data Source=$azureDbServerName.database.windows.net;Initial Catalog=$configurationDbName;Integrated Security=False;User ID=$azureSqlServerUserId;Password=$azureSqlServerPassword;Connect Timeout=60;Encrypt=False;TrustServerCertificate=False"
        $agmConfigDatabaseConnection1.Open()
        Write-Output "Connection OPEN for agm config"
        # Create command for agm master table  to update status.
        $agmConfigDatabaseCommand1= New-Object System.Data.SqlClient.SqlCommand
        $agmConfigDatabaseCommand1.Connection = $agmConfigDatabaseConnection1
 
        Write-Output "EXEC SP_UpdateAgmMasterAfterCreateMeeting '$createMeetingRbJobId',false,'$errorDesc'"
        $agmConfigDatabaseCommand1.CommandText = "EXEC SP_UpdateAgmMasterAfterCreateMeeting '$createMeetingRbJobId',false,'$errorDesc'"
        Write-Output "Executing query on agm master database."
        $agmConfigDatabaseCommand1.ExecuteNonQuery()
        $agmConfigDatabaseConnection1.Close()
        Write-Output "Connection closed."
        write-output "Completed status update in agm master table."
 
        write-output "Completed rollback."
 
    throw $_.Exception
    }