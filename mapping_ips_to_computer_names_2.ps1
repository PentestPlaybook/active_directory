Get-ADComputer -Filter * -Property Name | ForEach-Object {
    $dns = $_.Name
    try {
        $ip = [System.Net.Dns]::GetHostAddresses($dns) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -ExpandProperty IPAddressToString
        [PSCustomObject]@{ComputerName=$dns; IPAddress=$ip}
    } catch {
        Write-Output "${dns}: IP address not found"
    }
} | Format-Table -AutoSize
