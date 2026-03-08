<#
    .Synopsis
       Generates users, groups, OUs, computers in an active directory domain.  Then places ACLs on random OUs
    .DESCRIPTION
       This tool is for research purposes and training only.  Intended only for personal use.  This adds a large number of objects into a domain, and should never be run in production.
    .EXAMPLE
       .\Invoke-BadBlood.ps1 -UserCount 2500 -GroupCount 500 -ComputerCount 100
    .PARAMETER UserCount
       Number of users to create (default 2500).
    .PARAMETER GroupCount
       Number of groups to create (default 500).
    .PARAMETER ComputerCount
       Number of computers to create (default 100).
    .PARAMETER SkipOuCreation
       Skip the OU creation if you already have done it.
    .PARAMETER SkipLapsInstall
       Skip the LAPS deployment if you already have done it.
    .PARAMETER NonInteractive
       Make non-interactive for automation.
    .OUTPUTS
       [String]
    .NOTES
       Written by David Rowe, Blog secframe.com
       Twitter : @davidprowe
       I take no responsibility for any issues caused by this script.  I am not responsible if this gets run in a production domain.
       Thanks HuskyHacks for user/group/computer count modifications.
    .FUNCTIONALITY
       Adds a ton of stuff into a domain.  Adds Users, Groups, OUs, Computers, and a vast amount of ACLs in a domain.
    .LINK
       http://www.secframe.com/badblood
#>
[CmdletBinding()]

param
(
   [Parameter(Mandatory = $false, Position = 1, HelpMessage = 'Number of users to create (default 2500)')]
   [Int32]$UserCount = 50,

   [Parameter(Mandatory = $false, Position = 2, HelpMessage = 'Number of groups to create (default 500)')]
   [Int32]$GroupCount = 5,

   [Parameter(Mandatory = $false, Position = 3, HelpMessage = 'Number of computers to create (default 100)')]
   [Int32]$ComputerCount = 5,

   [Parameter(Mandatory = $false, HelpMessage = 'Skip the OU creation if you already have done it')]
   [switch]$SkipOuCreation,

   [Parameter(Mandatory = $false, HelpMessage = 'Skip the LAPS deployment if you already have done it')]
   [switch]$SkipLapsInstall,

   [Parameter(Mandatory = $false, HelpMessage = 'Make non-interactive for automation')]
   [switch]$NonInteractive
)

function Get-ScriptDirectory {
   Split-Path -Parent $PSCommandPath
}
$basescriptPath = Get-ScriptDirectory
$totalscripts   = 8
$i              = 0

Clear-Host
Write-Host "Welcome to BadBlood"
if (-not $NonInteractive) {
    Write-Host 'Press any key to continue...'
    Write-Host "`n"
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
Write-Host "The first tool that absolutely mucks up your TEST domain"
Write-Host "This tool is never meant for production and can totally screw up your domain"

if (-not $NonInteractive) {
    Write-Host 'Press any key to continue...'
    Write-Host "`n"
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
Write-Host "You are responsible for how you use this tool. It is intended for personal use only"
Write-Host "This is not intended for commercial use"
if (-not $NonInteractive) {
    Write-Host 'Press any key to continue...'
    Write-Host "`n"
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}
Write-Host "`n"
Write-Host "Domain size generated via parameters`n Users: $UserCount`n Groups: $GroupCount`n Computers: $ComputerCount"
Write-Host "`n"

$badblood = 'badblood'
if (-not $NonInteractive) {
    $badblood = Read-Host -Prompt "Type 'badblood' to deploy some randomness into a domain"
    $badblood = $badblood.ToLower()
    if ($badblood -ne 'badblood') { exit }
}

if ($badblood -eq 'badblood') {

    $Domain = Get-ADDomain

    # =========================================================================
    # LAPS
    # =========================================================================
    if (-not $PSBoundParameters.ContainsKey('SkipLapsInstall')) {
        Write-Progress -Activity "Random Stuff into A domain" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
        . ($basescriptPath + '\AD_LAPS_Install\InstallLAPSSchema.ps1')
        Write-Progress -Activity "Random Stuff into A domain: Install LAPS" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    }
    $i++

    # =========================================================================
    # OU Structure
    # =========================================================================
    if (-not $PSBoundParameters.ContainsKey('SkipOuCreation')) {
        . ($basescriptPath + '\AD_OU_CreateStructure\CreateOUStructure.ps1')
        Write-Progress -Activity "Random Stuff into A domain - Creating OUs" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    }
    $i++

    # =========================================================================
    # Shared pre-loaded data (available to all Create* functions via scope chain)
    # Pre-loading eliminates repeated disk I/O and AD queries inside each call.
    # =========================================================================
    $ousAll    = Get-ADOrganizationalUnit -Filter *
    $GlobalOUDNs  = [string[]]($ousAll | Select-Object -ExpandProperty DistinguishedName)
    $GlobalSetDC  = $Domain.pdcemulator
    $GlobalDNSRoot = $Domain.dnsroot
    $GlobalDomainDN = $Domain.distinguishedname

    # =========================================================================
    # User Creation  -  sequential, single-threaded
    #
    # Why not parallel?  AD's NTDS engine serialises all writes internally, so
    # parallel LDAP connections don't increase write throughput.  They only add
    # LDAP connection overhead, TCP handle pressure, and NTDS transaction
    # contention — which is what caused the DC to become unresponsive.
    # The real speedup comes from pre-loading name files (done below) so the
    # function never reads from disk inside the loop.
    # =========================================================================
    Write-Host "Creating $UserCount Users on Domain" -ForegroundColor Green
    Write-Progress -Activity "Random Stuff into A domain - Creating Users" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    $i++

    . ($basescriptPath + '\AD_Users_Create\CreateUsers.ps1')
    $GlobalScriptPath = $basescriptPath + '\AD_Users_Create\'

    Write-Host "  Pre-loading name files..." -ForegroundColor DarkGray
    $GlobalFemaleNames = [string[]](Get-Content ($GlobalScriptPath + 'Names\femalenames-usa-top1000.txt'))
    $GlobalMaleNames   = [string[]](Get-Content ($GlobalScriptPath + 'Names\malenames-usa-top1000.txt'))
    $GlobalFamilyNames = [string[]](Get-Content ($GlobalScriptPath + 'Names\familynames-usa-top1000.txt'))

    for ($u = 1; $u -le $UserCount; $u++) {
        CreateUser
        if ($u % 250 -eq 0 -or $u -eq $UserCount) {
            Write-Progress -Activity "Creating $UserCount Users" `
                -Status "$u / $UserCount" `
                -PercentComplete ($u / $UserCount * 100)
        }
    }
    Write-Progress -Activity "Creating $UserCount Users" -Completed

    # =========================================================================
    # Group Creation
    # =========================================================================
    $AllUsers = Get-ADUser -Filter *
    $GlobalUserSummary    = @($AllUsers | Select-Object SamAccountName, DistinguishedName)

    Write-Host "Creating $GroupCount Groups on Domain" -ForegroundColor Green
    Write-Progress -Activity "Random Stuff into A domain - Creating $GroupCount Groups" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    $i++

    . ($basescriptPath + '\AD_Groups_Create\CreateGroup.ps1')
    $GlobalGroupScriptPath = $basescriptPath + '\AD_Groups_Create\'
    $GlobalHotmailWords    = [string[]](Get-Content ($GlobalGroupScriptPath + 'hotmail.txt'))

    for ($g = 1; $g -le $GroupCount; $g++) {
        CreateGroup
        if ($g % 100 -eq 0 -or $g -eq $GroupCount) {
            Write-Progress -Activity "Creating $GroupCount Groups" `
                -Status "$g / $GroupCount" `
                -PercentComplete ($g / $GroupCount * 100)
        }
    }
    Write-Progress -Activity "Creating $GroupCount Groups" -Completed

    $Grouplist      = Get-ADGroup -Filter { GroupCategory -eq "Security" -and GroupScope -eq "Global" } -Properties isCriticalSystemObject
    $LocalGroupList = Get-ADGroup -Filter { GroupScope -eq "domainlocal" } -Properties isCriticalSystemObject

    # =========================================================================
    # Computer Creation
    # =========================================================================
    Write-Host "Creating $ComputerCount Computers on Domain" -ForegroundColor Green
    Write-Progress -Activity "Random Stuff into A domain - Creating Computers" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    $i++

    . ($basescriptPath + '\AD_Computers_Create\CreateComputers.ps1')
    $GlobalComputerScriptPath = $basescriptPath + '\AD_Computers_Create\'
    $Global3LetterCodes       = @(Import-Csv ($basescriptPath + '\AD_OU_CreateStructure\3lettercodes.csv'))

    for ($c = 1; $c -le $ComputerCount; $c++) {
        CreateComputer
        if ($c % 25 -eq 0 -or $c -eq $ComputerCount) {
            Write-Progress -Activity "Creating $ComputerCount Computers" `
                -Status "$c / $ComputerCount" `
                -PercentComplete ($c / $ComputerCount * 100)
        }
    }
    Write-Progress -Activity "Creating $ComputerCount Computers" -Completed

    $Complist = Get-ADComputer -Filter *

    # =========================================================================
    # Permission / ACL Creation
    # =========================================================================
    $i++
    Write-Host "Creating Permissions on Domain" -ForegroundColor Green
    Write-Progress -Activity "Random Stuff into A domain - Creating Random Permissions" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    . ($basescriptPath + '\AD_Permissions_Randomizer\GenerateRandomPermissions.ps1')

    # =========================================================================
    # Group Nesting
    # =========================================================================
    $i++
    Write-Host "Nesting objects into groups on Domain" -ForegroundColor Green
    . ($basescriptPath + '\AD_Groups_Create\AddRandomToGroups.ps1')
    Write-Progress -Activity "Random Stuff into A domain - Adding Stuff to Stuff and Things" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    AddRandomToGroups -Domain $Domain -Userlist $AllUsers -GroupList $Grouplist -LocalGroupList $LocalGroupList -complist $Complist

    # =========================================================================
    # SPN Generation
    # =========================================================================
    $i++
    Write-Host "Adding random SPNs to a few User and Computer Objects" -ForegroundColor Green
    Write-Progress -Activity "SPN Stuff Now" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    . ($basescriptpath + '\AD_Attack_Vectors\AD_SPN_Randomizer\CreateRandomSPNs.ps1')
    CreateRandomSPNs -SPNCount 50

    # =========================================================================
    # ASREP Roasting setup
    # =========================================================================
    Write-Host "Adding ASREP for a few users" -ForegroundColor Green
    Write-Progress -Activity "Adding ASREP Now" -Status "Progress:" -PercentComplete ($i / $totalscripts * 100)
    $ASREPCount = [Math]::Ceiling($AllUsers.Count * .05)
    $ASREPUsers = if ($ASREPCount -ge $AllUsers.Count) {
        $AllUsers
    } else {
        Get-Random -Count $ASREPCount -InputObject $AllUsers
    }

    . ($basescriptpath + '\AD_Attack_Vectors\ASREP_NotReqPreAuth.ps1')
    ADREP_NotReqPreAuth -UserList $ASREPUsers

    Write-Host "BadBlood complete." -ForegroundColor Green
}
