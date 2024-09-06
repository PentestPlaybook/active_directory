param (
    [string]$GroupCN
)

# Function to search LDAP with a query
function LDAPSearch {
    param (
        [string]$LDAPQuery
    )
    
    $PDC = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().PdcRoleOwner.Name
    $DN = ([adsi]'').distinguishedName 
    $LDAP = "LDAP://$PDC/$DN"

    $direntry = New-Object System.DirectoryServices.DirectoryEntry($LDAP)
    $dirsearcher = New-Object System.DirectoryServices.DirectorySearcher($direntry)
    $dirsearcher.Filter = $LDAPQuery
    return $dirsearcher.FindAll()
}

# Function to recursively unravel nested group memberships
function Get-NestedGroupMembers {
    param (
        [string]$GroupCN
    )

    # Get group members
    $group = LDAPSearch -LDAPQuery "(&(objectCategory=group)(cn=$GroupCN))"

    # Unravel the group members
    foreach ($member in $group.Properties.member) {
        Write-Host "Found member: $member"
        
        # Query the member to check if it is a group or a user
        $memberObject = LDAPSearch -LDAPQuery "(&(distinguishedName=$member))"
        
        foreach ($obj in $memberObject) {
            # Check if the object is a group or a user
            if ($obj.Properties.objectclass -contains "group") {
                Write-Host "Enumerating nested group: $($obj.Properties.cn)"
                # Recursively enumerate the nested group
                Get-NestedGroupMembers $obj.Properties.cn
            } elseif ($obj.Properties.objectclass -contains "user") {
                Write-Host "Found user member: $member"
                # Print out user details
                foreach ($prop in $obj.Properties.PropertyNames) {
                    $propValue = $obj.Properties[$prop]
                    Write-Host "${prop}: $($propValue)"
                }
                Write-Host "-------------------------------"
            }
        }
    }
}

# Start the recursive search with the provided group
Write-Host "Enumerating group: $GroupCN"
Get-NestedGroupMembers $GroupCN
