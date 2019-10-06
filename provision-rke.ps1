param(
    [string]$pandoraFqdn = 'pandora.rancher.test',
    [string]$roles = 'worker',
    [int]$rkeIndex = 0,
    [string]$rkeFqdn = 'rkew1.rancher.test',
    [string]$rkeIpAddress = '10.1.0.40',
    [string]$adminPassword = 'admin',
    [string]$rkeVersion = 'v0.3.0',
    [string]$k8sVersion = 'v1.16.1-rancher1-1',
    [string]$kubectlVersion = '1.16.1-00',
    [string]$krewVersion = 'v0.3.0'
)

if ($roles -ne 'worker') {
    throw "can only launch worker roles on windows. but tried to launch $roles"
}

# configure this host to be accessed by the rke ssh key.
Get-Content -Encoding ascii /vagrant/shared/ssh/rke_rsa.pub `
    | Add-Content -Encoding ascii (Resolve-Path ~/.ssh/authorized_keys)

# download install the binaries.
# see https://github.com/rancher/rke/releases
$archiveVersion = $rkeVersion.Substring(1)
$archiveName = "rke_windows-amd64.exe"
$archiveUrl = "https://github.com/rancher/rke/releases/download/v$archiveVersion/$archiveName"
$archiveHash = '9373cd6f0cc2368db5bff8d0f233bc0b1944cbc95c67511d212c500253c9a112'
$archivePath = "$env:ChocolateyInstall\bin\rke.exe"
Write-Host "Installing rke $archiveVersion..."
(New-Object System.Net.WebClient).DownloadFile($archiveUrl, $archivePath)
$archiveActualHash = (Get-FileHash $archivePath -Algorithm SHA256).Hash
if ($archiveActualHash -ne $archiveHash) {
    throw "the $archiveUrl file hash $archiveActualHash does not match the expected $archiveHash"
}

# dump versions.
rke --version
rke config --list-version --all                   # list supported k8s versions.
rke config --system-images --version $k8sVersion # list the system images.

# add this node to the cluster as a worker node.
cp /vagrant/shared/cluster.rkestate .
cp /vagrant/shared/cluster.yaml .
Add-Content -Encoding ascii cluster.yaml @"
  - hostname_override: $($rkeFqdn.Split('.')[0])
    address: $rkeFqdn
    internal_address: $rkeIpAddress
    user: vagrant
    role:
      - worker
"@

# bring up the cluster.
rke up --config cluster.yaml
