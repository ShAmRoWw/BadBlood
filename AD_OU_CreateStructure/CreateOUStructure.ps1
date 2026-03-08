#
# Creates the tiered OU structure for BadBlood.
# Safe to re-run: existing OUs are skipped silently.
#
function Get-ScriptDirectory {
    Split-Path -Parent $PSCommandPath
}
$scriptPath = Get-ScriptDirectory

$TopLevelOUs   = @('Admin', 'Tier 1', 'Tier 2', 'Stage', 'Quarantine', 'Grouper-Groups', 'People', 'Testing', '.SecFrame.com')
$AdminSubOUs   = @('Tier 0', 'Tier 1', 'Tier 2', 'Staging')
$AdminobjectOUs = @('Accounts', 'Servers', 'Devices', 'Permissions', 'Roles')
$skipSubOUs    = @('Deprovision', 'Quarantine', 'Groups')
$ObjectSubOUs  = @('ServiceAccounts', 'Groups', 'Devices', 'Test')

$3LetterCodeCSV = $scriptPath + '\3lettercodes.csv'

# Helper: create an OU only if it does not already exist
function New-OUSafe {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Description,
        [switch]$ProtectedFromAccidentalDeletion
    )
    $params = @{ Name = $Name; ErrorAction = 'Stop' }
    if ($Path)        { $params['Path']        = $Path }
    if ($Description) { $params['Description'] = $Description }
    if ($ProtectedFromAccidentalDeletion) { $params['ProtectedFromAccidentalDeletion'] = $true }

    try {
        New-ADOrganizationalUnit @params
    } catch [Microsoft.ActiveDirectory.Management.ADException] {
        # 0x2071 = objectAlreadyExists — skip silently
        if ($_.Exception.Message -notmatch 'already in use|already exists') {
            Write-Warning "OU '$Name': $($_.Exception.Message)"
        }
    } catch {
        Write-Warning "OU '$Name': $_"
    }
}

Set-Location C:\
$dn = (Get-ADDomain).distinguishedname

Write-Host "Creating Tiered OU Structure" -ForegroundColor Green
$topOUCount = $TopLevelOUs.Count
$x = 1

foreach ($name in $TopLevelOUs) {
    Write-Progress -Activity "Deploying OU Structure" -Status "Top Level OU Status:" -PercentComplete ($x / $topOUCount * 100)

    New-OUSafe -Name $name -ProtectedFromAccidentalDeletion
    $fulldn = "OU=$name,$dn"

    if ($name -eq $TopLevelOUs[0]) {
        # Admin sub-OUs
        foreach ($adminsubou in $AdminSubOUs) {
            New-OUSafe -Name $adminsubou -Path $fulldn
            $adminsubfulldn = "OU=$adminsubou,$fulldn"

            if ($adminsubou -ne 'Staging') {
                foreach ($AdminobjectOU in $AdminobjectOUs) {
                    switch ($adminsubou) {
                        'Tier 0' { $adminOUPrefix = 'T0-' }
                        'Tier 1' { $adminOUPrefix = 'T1-' }
                        'Tier 2' { $adminOUPrefix = 'T2-' }
                    }
                    New-OUSafe -Name ($adminOUPrefix + $AdminobjectOU) -Path $adminsubfulldn
                }
            }
        }
    }
    elseif ($skipSubOUs -contains $name) {
        # intentionally empty
    }
    elseif ($name -in @('Tier 1', 'Tier 2', 'Stage')) {
        $fulldn  = "OU=$name,$dn"
        $csvlist = Import-Csv $3LetterCodeCSV

        foreach ($ou in $csvlist) {
            New-OUSafe -Name $ou.name -Path $fulldn -Description $ou.description
            $csvdn = "OU=$($ou.name),$fulldn"

            foreach ($ObjectSubOU in $ObjectSubOUs) {
                New-OUSafe -Name $ObjectSubOU -Path $csvdn
            }
        }
    }
    elseif ($name -eq 'People') {
        $fulldn  = "OU=$name,$dn"
        $csvlist = Import-Csv $3LetterCodeCSV

        foreach ($ou in $csvlist) {
            New-OUSafe -Name $ou.name -Path $fulldn -Description $ou.description
        }
        New-OUSafe -Name 'Deprovisioned' -Path $fulldn -Description 'User accounts deprovisioned by the IDM System'
        New-OUSafe -Name 'Unassociated'  -Path $fulldn -Description 'User objects with no department affiliation'
    }

    $x++
}
