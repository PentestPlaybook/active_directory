# Ensure the Active Directory module is loaded
Import-Module ActiveDirectory

# Retrieve all computer accounts from Active Directory with their DNS host names
$computers = Get-ADComputer -Filter * -Property DNSHostName

# Resolve IP addresses for each computer and create a custom object for each
$computerIPs = foreach ($computer in $computers) {
    try {
        # Attempt to resolve the first IP address associated with the DNS host name
        $ipAddress = [System.Net.Dns]::GetHostAddresses($computer.DNSHostName)[0].IPAddressToString
        [PSCustomObject]@{
            ComputerName = $computer.Name
            IPAddress = $ipAddress
        }
    } catch {
        # If DNS resolution fails, log the failure
        Write-Output "Failed to resolve IP for $($computer.Name)"
    }
}

# Display the results in a formatted table
$computerIPs | Format-Table -AutoSize

# Export the results to a CSV file for further analysis or documentation
$computerIPs | Export-Csv -Path "C:\path\to\output\ComputerIPMappings.csv" -NoTypeInformation
