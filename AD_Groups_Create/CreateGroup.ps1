Function CreateGroup {
    <#
        .SYNOPSIS
            Creates a Group in an active directory environment based on random data

        .DESCRIPTION
            Starting with the root container this tool randomly places groups in the domain.

        .PARAMETER Domain
            The stored value of get-addomain.

        .PARAMETER OUList
            The stored value of get-adorganizationalunit -filter *.

        .PARAMETER UserList
            The stored value of get-aduser -filter *. Used to assign random managers.

        .PARAMETER ScriptDir
            The location of the script directory (must contain hotmail.txt).

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
    # Resolve DC
    # Priority: RunspacePool globals > parameters > positional args > AD query
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalSetDC -and $GlobalSetDC -ne '') {
        $setDC = $GlobalSetDC
    } elseif ($PSBoundParameters.ContainsKey('Domain')) {
        $setDC = $Domain.pdcemulator
    } elseif ($args[0]) {
        $setDC = $args[0].pdcemulator
    } else {
        $setDC = (Get-ADDomain).pdcemulator
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
    # Resolve UserList (only SamAccountName + DistinguishedName needed)
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
    # Resolve script path (for hotmail.txt)
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalGroupScriptPath -and $GlobalGroupScriptPath -ne '') {
        $groupscriptPath = $GlobalGroupScriptPath
    } elseif ($PSBoundParameters.ContainsKey('ScriptDir')) {
        $groupscriptPath = $ScriptDir
    } elseif ($args[3]) {
        $groupscriptPath = $args[3]
    } else {
        $groupscriptPath = "$((Get-Location).path)\AD_Groups_Create\"
    }

    # ---------------------------------------------------------------------------
    # Hotmail word list - use RunspacePool global or cache in script scope
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalHotmailWords -and $GlobalHotmailWords.Count -gt 0) {
        $_hotmailWords = $GlobalHotmailWords
    } else {
        if ($null -eq $script:_CachedHotmailWords) {
            $script:_CachedHotmailWords = [string[]](Get-Content ($groupscriptPath + '\hotmail.txt'))
        }
        $_hotmailWords = $script:_CachedHotmailWords
    }

    # ---------------------------------------------------------------------------
    # Pick random manager and OU
    # ---------------------------------------------------------------------------
    $ownerinfo   = Get-Random -InputObject $UserList
    $Description = 'User Group Created by Badblood github.com/davidprowe/badblood'

    if ($OUsAll[0] -is [string]) {
        $ouLocation = Get-Random -InputObject $OUsAll
    } else {
        $ouLocation = (Get-Random -InputObject $OUsAll).distinguishedname
    }

    # ---------------------------------------------------------------------------
    # Build group name
    # ---------------------------------------------------------------------------
    $samLen          = [Math]::Min(2, $ownerinfo.samaccountname.Length)
    $Groupnameprefix = $ownerinfo.samaccountname.Substring(0, $samLen)

    $word        = Get-Random -InputObject $_hotmailWords
    $application = try { $word.Substring(0, 9) } catch { $word.Substring(0, [Math]::Min(3, $word.Length)) }

    $functionint   = Get-Random -Minimum 1 -Maximum 101
    $function      = if ($functionint -le 25) { 'admingroup' } else { 'distlist' }
    $GroupNameFull = "$Groupnameprefix-$application-$function"

    # ---------------------------------------------------------------------------
    # Deduplicate name (fixed: $checkAcct reset each iteration)
    # ---------------------------------------------------------------------------
    $i = 1
    do {
        $checkAcct = $null
        try { $checkAcct = Get-ADGroup $GroupNameFull -Server $setDC -ErrorAction Stop }
        catch { break }
        $GroupNameFull = ($GroupNameFull -replace '\d+$', '') + $i
        $i++
    } while ($null -ne $checkAcct)

    # ---------------------------------------------------------------------------
    # Create group
    # ---------------------------------------------------------------------------
    try {
        New-ADGroup -Server $setDC `
            -Description $Description `
            -Name $GroupNameFull `
            -Path $ouLocation `
            -GroupCategory Security `
            -GroupScope Global `
            -ManagedBy $ownerinfo.distinguishedname
    } catch {}
}
