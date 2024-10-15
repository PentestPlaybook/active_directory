# Initialize DirectorySearcher
$searcher = New-Object DirectoryServices.DirectorySearcher
$searcher.Filter = "(&(objectCategory=computer))"
$searcher.PropertiesToLoad.Add("name") | Out-Null

# Find all computer objects and extract their names
$computers = $searcher.FindAll() | ForEach-Object { $_.Properties.name }

# Initialize an array to hold the results
$results = @()

# Iterate through each computer name to resolve its IP address
foreach ($computer in $computers) {
    $name = $computer

    try {
        # Attempt to resolve the computer name to an IP address
        $ipAddresses = [System.Net.Dns]::GetHostAddresses($name) | 
                       Where-Object { $_.AddressFamily -eq 'InterNetwork' } | 
                       Select-Object -ExpandProperty IPAddressToString

        # If multiple IPs are found, join them with commas
        $ip = if ($ipAddresses) { $ipAddresses -join ", " } else { "N/A" }
    }
    catch {
        # If resolution fails, mark IP as N/A
        $ip = "N/A"
    }

    # Create a custom object with ComputerName and IPAddress
    $results += [PSCustomObject]@{
        ComputerName = $name
        IPAddress    = $ip
    }
}

# Display the results in a formatted table
$results | Format-Table -AutoSize
