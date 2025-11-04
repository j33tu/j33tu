# Input bindings are passed in via param block.
param($Timer)
#Install-Module -Name Az.ResourceGraph -Force --debug
#install-module *az* -scope currentuser
# --- Configuration Variables (Update these) ---
$SubscriptionId = "fc3262c8-bd1f-4d90-8b17-08a6afa9b5ff"
$StorageResourceGroup = "avd"
$StorageAccountName = "avd8bae"
$ContainerName = "vm-status-reports"
# --- 1. Define Variables ---
# ...
#$LocalCSVPath = "./VMStatusReport.csv" # Temporary local path to store the CSV
#$BlobName = "VMStatusReport-$(Get-Date -Format 'yyyyMMdd_HHmmss').csv" # Unique name for the blob

# --- Step 1: Connect and Select Subscription ---
# Connect-AzAccount will be used if running locally. If running in an Azure Function
# with Managed Identity, authentication happens automatically or via Connect-AzAccount -Identity.
#Connect-AzAccount -Identity --debug
#Write-Host "query azure subscription" -verbose
#Get-AzSubscription -SubscriptionId $SubscriptionId -verbose

# --- Step 2: Get VM Status and Export to CSV ---
#Write-Host "Getting VM status and exporting to CSV..." -verbose

# Retrieve all VMs and their status, then select and format the desired properties.\
Write-Host "getting vm list available in this subscription" ForegroundColor Green
# --- 1. Define Variables ---
$SubscriptionID = "fc3262c8-bd1f-4d90-8b17-08a6afa9b5ff"     # The subscription to query
$StorageAccountName = "avd8bae"    # Target Storage Account Name
$ContainerName = "vm-status-reports"              # Target Blob Container Name
$LocalPath = "./VMReports"                  # Local folder to save the CSV (Must Exist!)

# Create the folder if it doesn't exist
if (-not (Test-Path $LocalPath)) {
    New-Item -Path $LocalPath -ItemType Directory | Out-Null -verbose
}

# Generate the date-based filename
$DateStamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$FileName = "VM_Status_Report_$DateStamp.csv"
$FilePath = Join-Path -Path $LocalPath -ChildPath $FileName

# --- 2. Connect and Select Subscription ---
# Ensure you are connected to Azure. Run 'Connect-AzAccount' first if not already logged in.
Write-Host "Connecting to Azure and selecting subscription: $SubscriptionID..." -verbose
Connect-AzAccount -Identity 
Select-AzSubscription -SubscriptionId $SubscriptionID | Out-Null -verbose

# --- 3. Get VM Status using Azure Resource Graph (Search-AzGraph) ---
Write-Host "Querying VM status using Azure Resource Graph..." -verbose

# Define KQL query... (Assume the KQL fix from prior step is applied)
# Kusto Query Language (KQL) to find VMs and extract their power state
$KQLQuery = @"
Resources
| where type =~ 'Microsoft.Compute/virtualMachines'
| project 
    Subscription = subscriptionId,
    ResourceGroup = resourceGroup,
    VMName = name,
    Location = location,
    PowerState = tostring(properties.extended.instanceView.powerState.displayStatus),
    VMSize = tostring(sku.name)
| order by ResourceGroup asc, VMName asc
"@ # <--- NO SPACE, NO TABS AFTER THIS LINE
$VMStatus = Search-AzGraph -Query $KQLQuery -Subscription $SubscriptionID

# --- 4. Prepare Data for Export ---

if ($VMStatus.Count -gt 0) {
    # If VMs are found, use the actual data
    $DataToExport = $VMStatus.Data
    Write-Host "Found $($VMStatus.Count) Virtual Machines."
} else {
    # If NO VMs are found, create a blank object with the correct property names 
    # to ensure the CSV file has headers.
    Write-Warning "No Virtual Machines found in subscription. Creating empty report file."
    
    $DataToExport = [PSCustomObject]@{
        Subscription  = ""
        ResourceGroup = ""
        VMName        = ""
        Location      = ""
        PowerState    = ""
        VMSize        = ""
    } | Select-Object Subscription, ResourceGroup, VMName, Location, PowerState, VMSize
}

# --- 5. Export Data to a Date-Named CSV File ---

Write-Host "Exporting data to CSV file: $FilePath" -verbose
$DataToExport | Export-Csv -Path $FilePath -NoTypeInformation -Force

Write-Host "CSV file created successfully: $FilePath" -verbose

# --- 6. Upload CSV to Azure Blob Storage ---
Write-Host "Uploading $FileName to $StorageAccountName/$ContainerName..."

# Get the Storage Account Context using the Resource Group
$StorageContext = (Get-AzStorageAccount -Name $StorageAccountName -ResourceGroupName $StorageResourceGroup).Context

# Upload the file
Set-AzStorageBlobContent -File $FilePath `
    -Container $ContainerName `
    -Blob $FileName `
    -Context $StorageContext `
    -Force | Out-Null

# --- 7. Clean up (Optional) ---
Remove-Item -Path $FilePath -Force
Write-Host "Local CSV file deleted." -verbose

