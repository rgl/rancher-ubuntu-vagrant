param(
    [string]$dnsServerIpAddress = '10.1.0.2'
)

# Override the DNS servers.
Get-DnsClientServerAddress -InterfaceAlias 'Ethernet*' `
    | Where-Object { $_.ServerAddresses } `
    | Set-DnsClientServerAddress -ServerAddresses $dnsServerIpAddress
