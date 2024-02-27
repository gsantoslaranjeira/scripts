$backupDirectory = ""
$ssrsUri = ""

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
function Import-ReportsAndSubscriptions($currentPath, $currentRsPath) {
    # Import reports
    $reportFiles = Get-ChildItem -Path $currentPath -Recurse -Filter *.rdl
    foreach ($reportFile in $reportFiles) {
        $reportRsPath = $reportFile.DirectoryName.Substring($currentPath.Length).Replace("\", "/").TrimStart("/")
        try {
            Write-RsCatalogItem -Proxy $proxy -Path $reportFile.FullName -RsFolder "/$reportRsPath"
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
Import-ReportsAndSubscriptions -currentPath $backupDirectory -currentRsPath "/"
