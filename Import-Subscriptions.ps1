param (
    [Parameter(Mandatory=$true)]
    [string]$backupDirectory,

    [Parameter(Mandatory=$true)]
    [string]$ssrsUri
)

Write-Host "Installing ReportingServicesTools"
Install-Module -Name ReportingServicesTools -Scope CurrentUser -Force

Write-Host "Importing ReportingServicesTools"
Import-Module ReportingServicesTools

$cred = Get-Credential

Write-Host "Starting new connection to [$ssrsUri] as [$($cred.Username)]"
$proxy = New-RsWebServiceProxy -ReportServerUri $ssrsUri -Credential $cred

Write-Host "Importing subscriptions"

function Import-Subscriptions($currentPath) {
    # Import subscriptions
    $subscriptionFiles = Get-ChildItem -Path $currentPath -Recurse -Filter *.xml
    foreach ($subscriptionFile in $subscriptionFiles) {
        try {
            Import-RsSubscriptionXml -Proxy $proxy -Path $subscriptionFile.FullName | Copy-RsSubscription -Proxy $proxy -Credential $cred
            Write-Host "Subscription from file '$($subscriptionFile.FullName)' imported."
        } catch {
            Write-Host "Error importing subscription from file '$($subscriptionFile.FullName)': $_"
        }
    }
}

# Import subscriptions
Import-Subscriptions -currentPath $backupDirectory
