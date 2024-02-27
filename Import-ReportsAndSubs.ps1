<#
.SYNOPSIS
    Import reports and subscriptions to SSRS.

.DESCRIPTION
    The way this script works is by creating folders in SSRS and importing reports and subscriptions with the same structure created by the ExportReportsAndSubs.ps1 script.

.PARAMETER backupDirectory
    The directory where the reports and subscriptions are stored.

.PARAMETER ssrsUri
    The URI of the SSRS server.

.PARAMETER overwrite
    If set to true, the reports and subscriptions will be overwritten if they already exist.

.EXAMPLE
    Import-ReportsAndSubs.ps1 -backupDirectory "C:\Backup" -ssrsUri "http://localhost/ReportServer" -overwrite $true
    Imports reports and subscriptions from "C:\Backup" to "http://localhost/ReportServer" and overwrites existing reports and subscriptions.

.EXAMPLE
    Import-ReportsAndSubs.ps1 -backupDirectory "C:\Backup" -ssrsUri "http://localhost/ReportServer"
    Imports reports and subscriptions from "C:\Backup" to "http://localhost/ReportServer" without overwriting existing reports and subscriptions.

.NOTES
    Ensure that the user running this sctipt has the necessary permissions to import reports and subscriptions to SSRS.
#>

param (
    [Parameter(Mandatory=$true)]
    [string]$backupDirectory,

    [Parameter(Mandatory=$true)]
    [string]$ssrsUri,

    [bool]$overwrite = $false
)

Write-Host "Installing ReportingServicesTools"
Install-Module -Name ReportingServicesTools -Scope CurrentUser -Force

Write-Host "Importing ReportingServicesTools"
Import-Module ReportingServicesTools

$cred = Get-Credential

Write-Host "Starting new connection to [$ssrsUri] as [$($cred.Username)]"
$proxy = New-RsWebServiceProxy -ReportServerUri $ssrsUri -Credential $cred

# Function to recursively create folders in SSRS
Write-Host "Creating folders"
function Add-FoldersRecursively($currentPath, $currentRsPath) {
    foreach ($item in Get-ChildItem -Path $currentPath -Directory) {
        if ($item.PSIsContainer) {
            $newRsPath = Join-Path -Path $currentRsPath -ChildPath $item.Name
            $newRsPath = $newRsPath -replace '\\', '/' -replace '\/', '/'
            try {
                $proxy.CreateFolder($item.Name, $currentRsPath, $null)
            } catch {}
            # Recursively call for subfolders
            Add-FoldersRecursively -currentPath $item.FullName -currentRsPath "$newRsPath"
        }
    }
}

Write-Host "Importing reports and subscriptions"
function Import-ReportsAndSubscriptions($currentPath, $currentRsPath, $overwrite) {
    # Import reports
    $reportFiles = Get-ChildItem -Path $currentPath -Recurse -Filter *.rdl
    foreach ($reportFile in $reportFiles) {
        $reportRsPath = $reportFile.DirectoryName.Substring($currentPath.Length).Replace("\", "/").TrimStart("/")
        try {
            Write-RsCatalogItem -Proxy $proxy -Path $reportFile.FullName -RsFolder "/$reportRsPath" -Overwrite:$overwrite
            Write-Host "Report '$($reportFile.Name)' imported to '$reportRsPath'."
        } catch {
            Write-Host "Error importing report '$($reportFile.Name)': $_"
        }

        # Import associated subscriptions
        $subscriptionFile = [IO.Path]::ChangeExtension($reportFile.FullName, ".xml")
        if (Test-Path $subscriptionFile) {
            $rsItem = ($currentRsPath.TrimEnd('/') + '/' + $reportFile.FullName.Substring($currentPath.Length).TrimStart('\')).Replace('\', '/').Replace('.rdl', '')
            try {
                $currentDataSource = $proxy.GetItemDataSources($rsItem)
                $dataSourceDefinition = $currentDataSource[0].Item
                $dataSourceDefinition.CredentialRetrieval = "None"
                $proxy.SetItemDataSources($rsItem, $currentDataSource)
                Import-RsSubscriptionXml -Proxy $proxy -Path $subscriptionFile | Copy-RsSubscription -Proxy $proxy -RsItem $rsItem -Credential $cred
                Write-Host "Subscription for report '$($reportFile.Name)' imported."
            } catch {
                Write-Host "Error importing subscription for report '$($reportFile.Name)': $_"
            }
        }
    }
}

# Create folders and import reports and subscriptions
Add-FoldersRecursively -currentPath $backupDirectory -currentRsPath "/"
Import-ReportsAndSubscriptions -currentPath $backupDirectory -currentRsPath "/" -overwrite $overwrite
