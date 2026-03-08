################################
# Create Computer Objects
################################
Function CreateComputer {
    <#
        .SYNOPSIS
            Creates a Computer Object in an active directory environment based on random data

        .DESCRIPTION
            Starting with the root container this tool randomly places computers in the domain.

        .PARAMETER Domain
            The stored value of get-addomain.

        .PARAMETER OUList
            The stored value of get-adorganizationalunit -filter *.

        .PARAMETER UserList
            The stored value of get-aduser -filter *. Used to assign random managers.

        .PARAMETER ScriptDir
            The location of the script directory (used to locate 3lettercodes.csv).

        .NOTES
            Author's blog: https://www.secframe.com
    #>
    [CmdletBinding()]

    param
    (
        [Parameter(Mandatory = $false, Position = 1,
            HelpMessage = 'Supply a result from get-addomain')]
            [Object[]]$Domain,
        [Parameter(Mandatory = $false, Position = 2,
            HelpMessage = 'Supply a result from get-adorganizationalunit -filter *')]
            [Object[]]$OUList,
        [Parameter(Mandatory = $false, Position = 3,
            HelpMessage = 'Supply a result from get-aduser -filter *')]
            [Object[]]$UserList,
        [Parameter(Mandatory = $false, Position = 4,
            HelpMessage = 'Supply the script directory for where this script is stored')]
            [string]$ScriptDir
    )

    # ---------------------------------------------------------------------------
    # Resolve DC and domain DN
    # Priority: RunspacePool globals > parameters > positional args > AD query
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalSetDC -and $GlobalSetDC -ne '') {
        $setDC = $GlobalSetDC
        $dn    = $GlobalDomainDN
    } elseif ($PSBoundParameters.ContainsKey('Domain')) {
        $setDC = $Domain.pdcemulator
        $dn    = $Domain.distinguishedname
    } elseif ($args[0]) {
        $setDC = $args[0].pdcemulator
        $dn    = $args[0].distinguishedname
    } else {
        $d     = Get-ADDomain
        $setDC = $d.pdcemulator
        $dn    = $d.distinguishedname
    }

    # ---------------------------------------------------------------------------
    # Resolve OU list
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalOUDNs -and $GlobalOUDNs.Count -gt 0) {
        $OUsAll = $GlobalOUDNs
    } elseif ($PSBoundParameters.ContainsKey('OUList')) {
        $OUsAll = $OUList
    } elseif ($args[1]) {
        $OUsAll = $args[1]
    } else {
        $OUsAll = @(Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty DistinguishedName)
    }

    # ---------------------------------------------------------------------------
    # Resolve UserList
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalUserSummary -and $GlobalUserSummary.Count -gt 0) {
        $UserList = $GlobalUserSummary
    } elseif ($PSBoundParameters.ContainsKey('UserList')) {
        # already set
    } elseif ($args[2]) {
        $UserList = $args[2]
    } else {
        $UserList = Get-ADUser -ResultSetSize 2500 -Server $setDC -Filter *
    }

    # ---------------------------------------------------------------------------
    # Resolve script path and 3-letter codes
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalComputerScriptPath -and $GlobalComputerScriptPath -ne '') {
        $scriptpath = $GlobalComputerScriptPath
    } elseif ($PSBoundParameters.ContainsKey('ScriptDir')) {
        $scriptpath = $ScriptDir
    } elseif ($args[3]) {
        $scriptpath = $args[3]
    } else {
        $scriptpath = "$((Get-Location).path)\AD_Computers_Create\"
    }

    # Use pre-loaded 3-letter codes or cache from disk
    if ($null -ne $Global3LetterCodes -and $Global3LetterCodes.Count -gt 0) {
        $3lettercodes = $Global3LetterCodes
    } else {
        if ($null -eq $script:_Cached3LetterCodes) {
            $scriptparent = (Get-Item $scriptpath -ErrorAction SilentlyContinue).Parent.FullName
            if (-not $scriptparent) { $scriptparent = Split-Path $scriptpath -Parent }
            $csvPath = Join-Path $scriptparent 'AD_OU_CreateStructure\3lettercodes.csv'
            $script:_Cached3LetterCodes = Import-Csv $csvPath
        }
        $3lettercodes = $script:_Cached3LetterCodes
    }

    # ---------------------------------------------------------------------------
    # Pick random manager
    # ---------------------------------------------------------------------------
    $ownerinfo = Get-Random -InputObject $UserList
    $adminID   = $env:USERNAME

    # ---------------------------------------------------------------------------
    # Build computer name prefix
    # ---------------------------------------------------------------------------
    $computernameprefix1 = (Get-Random -InputObject $3lettercodes).NAME
    $computernameprefix3 = ''

    $WorkstationOrServer = Get-Random -InputObject @(0, 1)   # 0 = workstation, 1 = server
    $WorkstationType     = Get-Random -InputObject @(0, 1, 2) # 0 = desktop, 1 = laptop, 2 = VM

    if ($WorkstationOrServer -eq 0) {
        $computernameprefix2 = switch ($WorkstationType) {
            0 { 'WWKS' }
            1 { 'WLPT' }
            default { 'WVIR' }
        }
    } else {
        $ServerApplication   = Get-Random -InputObject @(0, 1, 2, 3, 4, 5)
        $computernameprefix2 = ''
        $computernameprefix3 = switch ($ServerApplication) {
            0 { 'APPS' }
            1 { 'WEBS' }
            2 { 'DBAS' }
            3 { 'SECS' }
            4 { 'CTRX' }
            default { 'APPS' }
        }
    }

    $computernameprefixfull = $computernameprefix1 + $computernameprefix2 + $computernameprefix3
    $cnSearch = $computernameprefixfull + '*'

    # ---------------------------------------------------------------------------
    # Pick OU location
    # ---------------------------------------------------------------------------
    if ($OUsAll[0] -is [string]) {
        $ouLocation = Get-Random -InputObject $OUsAll
    } else {
        $ouLocation = (Get-Random -InputObject $OUsAll).distinguishedname
    }

    # ---------------------------------------------------------------------------
    # Build unique computer name
    # Fetch existing computers with this prefix and increment the counter.
    # ---------------------------------------------------------------------------
    # Wrap in @() to ensure array behaviour when 0 or 1 results are returned
    $comps = @(Get-ADComputer -Server $setDC -Filter { (name -like $cnSearch) -and (name -notlike '*9999*') } |
               Sort-Object Name | Select-Object Name)

    $checkforDupe = 0
    if ($comps.Count -eq 0) {
        $i = 0
        do {
            $compname = $computernameprefixfull + ([convert]::ToInt32('1000000') + $i)
            $i += Get-Random -Minimum 1 -Maximum 10
            try   { $null = Get-ADComputer $compname -Server $setDC; $checkforDupe = 0 }
            catch { $checkforDupe = 1 }
        } while ($checkforDupe -eq 0)
    } else {
        $i = 1
        do {
            try {
                $lastNum  = [convert]::ToInt32(
                    ($comps[-1].Name).Substring($computernameprefixfull.Length), 10)
                $compname = $computernameprefixfull + ($lastNum + $i)
            } catch {
                $compname = $computernameprefixfull + ([convert]::ToInt32('1000000') + $i)
            }
            try   { $null = Get-ADComputer $compname -Server $setDC; $checkforDupe = 0 }
            catch { $checkforDupe = 1 }
            $i++
        } while ($checkforDupe -eq 0)
    }

    # ---------------------------------------------------------------------------
    # Optionally assign SPN (~10% of computers)
    # ---------------------------------------------------------------------------
    $sam = $compname + '$'
    [System.Collections.ArrayList]$att_to_add = @()
    if ((Get-Random -Minimum 1 -Maximum 101) -le 10) {
        [void]$att_to_add.Add('servicePrincipalName')
        $servicePrincipalName = "HOST/$compname"
    }

    $description = 'Created with secframe.com/badblood.'
    $manager     = $ownerinfo.distinguishedname

    try {
        New-ADComputer -Server $setDC -Name $compname -DisplayName $compname `
            -Enabled $true -Path $ouLocation -ManagedBy $manager `
            -SAMAccountName $sam -Description $description
    } catch {
        try {
            New-ADComputer -Server $setDC -Name $compname -DisplayName $compname `
                -Enabled $true -ManagedBy $manager `
                -SAMAccountName $sam -Description $description
        } catch { return }
    }

    # ---------------------------------------------------------------------------
    # Set additional attributes (e.g. SPN)
    # ---------------------------------------------------------------------------
    try {
        $result = Get-ADComputer $sam -Server $setDC
        foreach ($a in $att_to_add) {
            $var = Get-Variable -Name $a -ValueOnly -ErrorAction SilentlyContinue
            if ($null -ne $var) {
                $result | Set-ADComputer -Server $setDC -Replace @{ $a = $var }
            }
        }
    } catch {}
}
