Function AddRandomToGroups {

    [CmdletBinding()]

    param
    (
        [Parameter(Mandatory = $false, Position = 1,
            HelpMessage = 'Supply a result from get-addomain')]
            [Object[]]$Domain,
        [Parameter(Mandatory = $false, Position = 2,
            HelpMessage = 'Supply a result from get-aduser -filter *')]
            [Object[]]$UserList,
        [Parameter(Mandatory = $false, Position = 3,
            HelpMessage = 'Supply a result from Get-ADGroup -Filter { GroupCategory -eq "Security" -and GroupScope -eq "Global" } -Properties isCriticalSystemObject')]
            [Object[]]$GroupList,
        [Parameter(Mandatory = $false, Position = 4,
            HelpMessage = 'Supply a result from Get-ADGroup -Filter { GroupScope -eq "domainlocal" } -Properties isCriticalSystemObject')]
            [Object[]]$LocalGroupList,
        [Parameter(Mandatory = $false, Position = 5,
            HelpMessage = 'Supply a result from Get-ADComputer -f *')]
            [Object[]]$CompList
    )

    if (!$PSBoundParameters.ContainsKey('Domain')) {
        $dom     = Get-ADDomain
        $setDC   = $dom.pdcemulator
        $dnsroot = $dom.dnsroot
    } else {
        $setDC   = $Domain.pdcemulator
        $dnsroot = $Domain.dnsroot
    }
    if (!$PSBoundParameters.ContainsKey('UserList')) {
        $allUsers = Get-ADUser -Filter *
    } else {
        $allUsers = $UserList
    }
    if (!$PSBoundParameters.ContainsKey('GroupList')) {
        $allGroups = Get-ADGroup -Filter { GroupCategory -eq "Security" -and GroupScope -eq "Global" } -Properties isCriticalSystemObject
    } else {
        $allGroups = $GroupList
    }
    if (!$PSBoundParameters.ContainsKey('LocalGroupList')) {
        $allGroupsLocal = Get-ADGroup -Filter { GroupScope -eq "domainlocal" } -Properties isCriticalSystemObject
    } else {
        $allGroupsLocal = $LocalGroupList
    }
    if (!$PSBoundParameters.ContainsKey('CompList')) {
        $allcomps = Get-ADComputer -Filter *
    } else {
        $allcomps = $CompList
    }

    # Ensure AD PSDrive is available
    try { Push-Location 'AD:\' } catch { Set-Location C:\ }

    # -------------------------------------------------------------------------
    # Helper: batch-add members to a group in chunks of $ChunkSize.
    # This avoids hitting LDAP payload limits and is dramatically faster than
    # one Add-ADGroupMember call per member.
    # -------------------------------------------------------------------------
    function Add-GroupMemberBatch {
        param(
            [string]$GroupDN,
            [System.Collections.Generic.List[object]]$Members,
            [int]$ChunkSize = 500
        )
        # Deduplicate by DistinguishedName to avoid "already a member" errors
        $unique = @($Members | Sort-Object -Property DistinguishedName -Unique)
        for ($start = 0; $start -lt $unique.Count; $start += $ChunkSize) {
            $end   = [Math]::Min($start + $ChunkSize - 1, $unique.Count - 1)
            $chunk = $unique[$start..$end]
            try { Add-ADGroupMember -Identity $GroupDN -Members $chunk } catch {}
        }
    }

    $UsersInGroupCount  = [math]::Round($allUsers.Count * .8)
    $GroupsInGroupCount = [math]::Round($allGroups.Count * .2)
    $CompsInGroupCount  = [math]::Round($allcomps.Count * .1)

    $AddUserstoGroups  = if ($UsersInGroupCount -ge $allUsers.Count) { $allUsers } else { Get-Random -Count $UsersInGroupCount -InputObject $allUsers }
    $allGroupsFiltered = @($allGroups | Where-Object { $_.isCriticalSystemObject -ne $true })
    $allGroupsCrit     = @($allGroups | Where-Object { $_.isCriticalSystemObject -eq $true } |
                           Where-Object { $_.Name -ne 'Domain Users' -and $_.Name -ne 'Domain Guests' })

    if ($allGroupsFiltered.Count -eq 0) {
        Write-Warning "No non-critical groups found - skipping group membership assignment."
        try { Pop-Location } catch {}
        return
    }

    # =========================================================================
    # Users -> non-critical groups
    # Instead of N*M individual Add-ADGroupMember calls, pre-compute all
    # assignments and then batch-add per group.  For 100k users x avg 5 groups
    # this reduces ~500k calls to ~500 batch calls.
    # =========================================================================
    Write-Host "  Computing user-to-group assignments..." -ForegroundColor DarkGray
    $userGroupBuckets = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()

    foreach ($user in $AddUserstoGroups) {
        $num = Get-Random -Minimum 1 -Maximum 11
        for ($n = 0; $n -le $num; $n++) {
            $g = (Get-Random -InputObject $allGroupsFiltered).DistinguishedName
            if (-not $userGroupBuckets.ContainsKey($g)) {
                $userGroupBuckets[$g] = [System.Collections.Generic.List[object]]::new()
            }
            $userGroupBuckets[$g].Add($user)
        }
    }

    Write-Host "  Batch-adding users to $($userGroupBuckets.Count) groups..." -ForegroundColor DarkGray
    $gIdx = 0
    foreach ($dn in $userGroupBuckets.Keys) {
        $gIdx++
        Write-Progress -Activity "Adding users to groups" `
            -Status "$gIdx / $($userGroupBuckets.Count)" `
            -PercentComplete ($gIdx / $userGroupBuckets.Count * 100)
        Add-GroupMemberBatch -GroupDN $dn -Members $userGroupBuckets[$dn]
    }
    Write-Progress -Activity "Adding users to groups" -Completed

    # =========================================================================
    # Users -> critical groups (small counts, direct add)
    # =========================================================================
    foreach ($grp in $allGroupsCrit) {
        $num = Get-Random -Minimum 2 -Maximum 6
        try { Add-ADGroupMember -Identity $grp -Members (Get-Random -Count $num -InputObject $allUsers) } catch {}
    }

    # =========================================================================
    # Users -> local groups
    # =========================================================================
    foreach ($grp in $allGroupsLocal) {
        $num = Get-Random -Minimum 1 -Maximum 4
        try { Add-ADGroupMember -Identity $grp -Members (Get-Random -Count $num -InputObject $allUsers) } catch {}
    }

    # =========================================================================
    # Group nesting: groups -> groups (batch approach)
    # =========================================================================
    $AddGroupstoGroups = Get-Random -Count $GroupsInGroupCount -InputObject $allGroupsFiltered
    $groupNestBuckets  = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()

    foreach ($group in $AddGroupstoGroups) {
        $num = Get-Random -Minimum 1 -Maximum 3
        for ($n = 0; $n -le $num; $n++) {
            $g = (Get-Random -InputObject $allGroupsFiltered).DistinguishedName
            if (-not $groupNestBuckets.ContainsKey($g)) {
                $groupNestBuckets[$g] = [System.Collections.Generic.List[object]]::new()
            }
            $groupNestBuckets[$g].Add($group)
        }
    }
    foreach ($dn in $groupNestBuckets.Keys) {
        Add-GroupMemberBatch -GroupDN $dn -Members $groupNestBuckets[$dn]
    }

    # Critical groups -> random non-critical groups
    foreach ($grp in $allGroupsCrit) {
        $num = Get-Random -Minimum 1 -Maximum 4
        for ($n = 0; $n -le $num; $n++) {
            $randogroup = Get-Random -InputObject $allGroupsFiltered
            try { Add-ADGroupMember -Identity $randogroup -Members $grp } catch {}
        }
    }

    # =========================================================================
    # Computers -> groups (batch approach)
    # =========================================================================
    $addcompstogroups = Get-Random -Count $CompsInGroupCount -InputObject $allcomps
    $compGroupBuckets = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()

    foreach ($comp in $addcompstogroups) {
        $num = Get-Random -Minimum 1 -Maximum 6
        for ($n = 0; $n -le $num; $n++) {
            $g = (Get-Random -InputObject $allGroupsFiltered).DistinguishedName
            if (-not $compGroupBuckets.ContainsKey($g)) {
                $compGroupBuckets[$g] = [System.Collections.Generic.List[object]]::new()
            }
            $compGroupBuckets[$g].Add($comp)
        }
    }
    foreach ($dn in $compGroupBuckets.Keys) {
        Add-GroupMemberBatch -GroupDN $dn -Members $compGroupBuckets[$dn]
    }

    try { Pop-Location } catch {}
}
