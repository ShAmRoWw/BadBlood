Function CreateUser{

    <#
        .SYNOPSIS
            Creates a user in an active directory environment based on random data

        .DESCRIPTION
            Starting with the root container this tool randomly places users in the domain.

        .PARAMETER Domain
            The stored value of get-addomain is used for this.  It is used to call the PDC and other items in the domain

        .PARAMETER OUList
            The stored value of get-adorganizationalunit -filter *.  This is used to place users in random locations.

        .PARAMETER ScriptDir
            The location of the script.  Pulling this into a parameter to attempt to speed up processing.

        .EXAMPLE
            createuser -Domain (Get-ADDomain) -OUList (Get-ADOrganizationalUnit -Filter *) -ScriptDir 'C:\BadBlood\AD_Users_Create\'

        .NOTES
            Unless required by applicable law or agreed to in writing, software
            distributed under the License is distributed on an "AS IS" BASIS,
            WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
            See the License for the specific language governing permissions and
            limitations under the License.

            Author's blog: https://www.secframe.com
    #>
    [CmdletBinding()]

    param
    (
        [Parameter(Mandatory = $false,
            Position = 1,
            HelpMessage = 'Supply a result from get-addomain')]
            [Object[]]$Domain,
        [Parameter(Mandatory = $false,
            Position = 2,
            HelpMessage = 'Supply a result from get-adorganizationalunit -filter *')]
            [Object[]]$OUList,
        [Parameter(Mandatory = $false,
            Position = 3,
            HelpMessage = 'Supply the script directory for where this script is stored')]
        [string]$ScriptDir
    )

    # ---------------------------------------------------------------------------
    # Resolve DC and DNS root
    # Priority: RunspacePool globals > named parameters > positional args > AD query
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalSetDC -and $GlobalSetDC -ne '') {
        $setDC   = $GlobalSetDC
        $dnsroot = $GlobalDNSRoot
    } elseif ($PSBoundParameters.ContainsKey('Domain')) {
        $setDC   = $Domain.pdcemulator
        $dnsroot = $Domain.dnsroot
    } elseif ($args[0]) {
        $setDC   = $args[0].pdcemulator
        $dnsroot = $args[0].dnsroot
    } else {
        $d       = Get-ADDomain
        $setDC   = $d.pdcemulator
        $dnsroot = $d.dnsroot
    }

    # ---------------------------------------------------------------------------
    # Resolve OU list
    # GlobalOUDNs is a pre-computed string[] of DistinguishedNames set by RunspacePool
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalOUDNs -and $GlobalOUDNs.Count -gt 0) {
        $OUsAll = $GlobalOUDNs          # already a string array
    } elseif ($PSBoundParameters.ContainsKey('OUList')) {
        $OUsAll = $OUList
    } elseif ($args[1]) {
        $OUsAll = $args[1]
    } else {
        $OUsAll = @(Get-ADOrganizationalUnit -Filter * | Select-Object -ExpandProperty DistinguishedName)
    }

    # ---------------------------------------------------------------------------
    # Resolve script path
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalScriptPath -and $GlobalScriptPath -ne '') {
        $scriptpath = $GlobalScriptPath
    } elseif ($PSBoundParameters.ContainsKey('ScriptDir')) {
        $scriptpath = $ScriptDir
    } elseif ($args[2]) {
        $scriptpath = $args[2]
    } else {
        $scriptpath = "$((Get-Location).path)\AD_Users_Create\"
    }

    # ---------------------------------------------------------------------------
    # Name arrays - use RunspacePool globals if available; otherwise load from disk
    # and cache in script scope so subsequent calls within the same runspace skip I/O.
    # ---------------------------------------------------------------------------
    if ($null -ne $GlobalFamilyNames -and $GlobalFamilyNames.Count -gt 0) {
        $_FamilyNames = $GlobalFamilyNames
        $_FemaleNames = $GlobalFemaleNames
        $_MaleNames   = $GlobalMaleNames
    } else {
        if ($null -eq $script:_CachedFamilyNames) {
            $script:_CachedFamilyNames = [string[]](Get-Content "$scriptpath\Names\familynames-usa-top1000.txt")
            $script:_CachedFemaleNames = [string[]](Get-Content "$scriptpath\Names\femalenames-usa-top1000.txt")
            $script:_CachedMaleNames   = [string[]](Get-Content "$scriptpath\Names\malenames-usa-top1000.txt")
        }
        $_FamilyNames = $script:_CachedFamilyNames
        $_FemaleNames = $script:_CachedFemaleNames
        $_MaleNames   = $script:_CachedMaleNames
    }

    # ---------------------------------------------------------------------------
    # Password generator (unchanged from original)
    # ---------------------------------------------------------------------------
    function New-SWRandomPassword {
        <#
        .Synopsis
           Generates one or more complex passwords designed to fulfill the requirements for Active Directory
        .DESCRIPTION
           Generates one or more complex passwords designed to fulfill the requirements for Active Directory
        .OUTPUTS
           [String]
        .NOTES
           Written by Simon Wahlin, blog.simonw.se
        .LINK
           http://blog.simonw.se/powershell-generating-random-password-for-active-directory/
        #>
        [CmdletBinding(DefaultParameterSetName='FixedLength',ConfirmImpact='None')]
        [OutputType([String])]
        Param
        (
            [Parameter(Mandatory=$false, ParameterSetName='RandomLength')]
            [ValidateScript({$_ -gt 0})]
            [Alias('Min')]
            [int]$MinPasswordLength = 12,

            [Parameter(Mandatory=$false, ParameterSetName='RandomLength')]
            [ValidateScript({
                    if($_ -ge $MinPasswordLength){$true}
                    else{Throw 'Max value cannot be lesser than min value.'}})]
            [Alias('Max')]
            [int]$MaxPasswordLength = 20,

            [Parameter(Mandatory=$false, ParameterSetName='FixedLength')]
            [ValidateRange(1,2147483647)]
            [int]$PasswordLength = 8,

            [String[]]$InputStrings = @('abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '23456789', '!#%&'),

            [String] $FirstChar,

            [ValidateRange(1,2147483647)]
            [int]$Count = 1
        )
        Begin {
            Function Get-Seed{
                $RandomBytes = New-Object -TypeName 'System.Byte[]' 4
                $Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
                $Random.GetBytes($RandomBytes)
                [BitConverter]::ToUInt32($RandomBytes, 0)
            }
        }
        Process {
            For($iteration = 1;$iteration -le $Count; $iteration++){
                $Password = @{}
                [char[][]]$CharGroups = $InputStrings
                $AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

                if($PSCmdlet.ParameterSetName -eq 'RandomLength')
                {
                    if($MinPasswordLength -eq $MaxPasswordLength) {
                        $PasswordLength = $MinPasswordLength
                    } else {
                        $PasswordLength = ((Get-Seed) % ($MaxPasswordLength + 1 - $MinPasswordLength)) + $MinPasswordLength
                    }
                }

                if($PSBoundParameters.ContainsKey('FirstChar')){
                    $Password.Add(0,$FirstChar[((Get-Seed) % $FirstChar.Length)])
                }
                Foreach($Group in $CharGroups) {
                    if($Password.Count -lt $PasswordLength) {
                        $Index = Get-Seed
                        While ($Password.ContainsKey($Index)){
                            $Index = Get-Seed
                        }
                        $Password.Add($Index,$Group[((Get-Seed) % $Group.Count)])
                    }
                }

                for($i=$Password.Count;$i -lt $PasswordLength;$i++) {
                    $Index = Get-Seed
                    While ($Password.ContainsKey($Index)){
                        $Index = Get-Seed
                    }
                    $Password.Add($Index,$AllChars[((Get-Seed) % $AllChars.Count)])
                }
                Write-Output -InputObject $(-join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value))
            }
        }
    }

    # ---------------------------------------------------------------------------
    # Pick a random OU location (handles both string[] and AD object arrays)
    # ---------------------------------------------------------------------------
    if ($OUsAll[0] -is [string]) {
        $ouLocation = Get-Random -InputObject $OUsAll
    } else {
        $ouLocation = (Get-Random -InputObject $OUsAll).distinguishedname
    }

    # ---------------------------------------------------------------------------
    # Determine account type and build name
    # ---------------------------------------------------------------------------
    $accountType = Get-Random -Minimum 1 -Maximum 101

    if ($accountType -le 3) {
        # Service account (~3% chance)
        $nameSuffix = 'SA'
        $name = "$(Get-Random -Minimum 100 -Maximum 9999999999)$nameSuffix"
    } else {
        $surname   = Get-Random -InputObject $_FamilyNames
        $genderpreference = Get-Random -InputObject @(0, 1)
        if ($genderpreference -eq 0) {
            $givenname = Get-Random -InputObject $_FemaleNames
        } else {
            $givenname = Get-Random -InputObject $_MaleNames
        }
        $name = "${givenname}_${surname}"
    }

    $description = 'Created with secframe.com/badblood.'
    $pwd = New-SWRandomPassword -MinPasswordLength 22 -MaxPasswordLength 25

    $passwordinDesc = Get-Random -Minimum 1 -Maximum 1001
    if ($passwordinDesc -lt 10) {
        $description = "Just so I dont forget my password is $pwd"
    }

    if ($name.Length -gt 20) {
        $name = $name.Substring(0, 20)
    }

    # ---------------------------------------------------------------------------
    # Create user - skip pre-check, let New-ADUser fail on duplicate (faster)
    # ---------------------------------------------------------------------------
    try {
        New-ADUser -Server $setDC `
            -Description $description `
            -DisplayName $name `
            -Name $name `
            -SamAccountName $name `
            -Surname $name `
            -Enabled $true `
            -Path $ouLocation `
            -AccountPassword (ConvertTo-SecureString $pwd -AsPlainText -Force) `
            -ErrorAction Stop
    } catch {
        $pwd = ''
        return
    }

    $pwd = ''

    # ---------------------------------------------------------------------------
    # Randomly set Does-Not-Require-Pre-Auth (~2% of users)
    # ---------------------------------------------------------------------------
    $setASREP = Get-Random -Minimum 1 -Maximum 1001
    if ($setASREP -lt 20) {
        try { Get-ADUser $name -Server $setDC | Set-ADAccountControl -DoesNotRequirePreAuth:$true } catch {}
    }

    # ---------------------------------------------------------------------------
    # Set UPN
    # ---------------------------------------------------------------------------
    $upn = "$name@$dnsroot"
    try { Set-ADUser -Identity $name -Server $setDC -UserPrincipalName $upn } catch {}
}
