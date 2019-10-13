param(
    [string]$pandoraFqdn = 'pandora.rancher.test',
    [string]$nodeIpAddress = '10.1.0.20',
    [string]$kubectlVersion = '1.16.1'
)

$registryHost = "${pandoraFqdn}:5000"
$registryUsername = 'vagrant'
$registryPassword = 'vagrant'

# install kubectl.
choco install -y kubernetes-cli --version $kubectlVersion

# copy kubectl configuration.
mkdir ~/.kube | Out-Null
cp C:/vagrant/shared/example-cluster-admin.conf ~/.kube/config

# register this node as an windows worker.
$rancherNodeCommand = Get-Content -Raw C:/vagrant/shared/rancher-windows-registration-node-command.cmd
$rancherAgentRegistrationCommand = $rancherNodeCommand -replace ' (\| iex)',("
    --address $nodeIpAddress
    --internal-address $nodeIpAddress
    --worker
    `$1
    " -replace "`n\s*",' ')
Write-Host "registering this node as a rancher-agent with $rancherAgentRegistrationCommand..."
cmd.exe /c $rancherAgentRegistrationCommand

# wait for this node to be Ready.
# e.g. uworker1   Ready    worker   2m9s   v1.16.1
$nodeName = $env:COMPUTERNAME.ToLower()
Write-Host "waiting for node $nodeName to be ready..."
while ($true) {
    $status = kubectl get nodes $nodeName 2>$null | Where-Object {$_ -match "$node_name\s+Ready\s+"}
    if ($status) {
        break
    }
    Start-Sleep -Seconds 3
}
Write-Host 'node ready!'

# login into the registry.
Write-Host "logging in the registry..."
$registryPassword | docker login $registryHost --username "$registryUsername" --password-stdin

# show summary.
Write-Title 'Windows version from host'
cmd /c ver
Write-Title 'Windows version from container'
docker run --rm mcr.microsoft.com/windows/nanoserver:1809 cmd /c ver
Write-Title 'Network configuration from container'
docker run --rm mcr.microsoft.com/windows/nanoserver:1809 ipconfig /all
Write-Title 'Network routing table from container'
docker run --rm mcr.microsoft.com/windows/nanoserver:1809 route print
Write-Title "Ping $pandoraFqdn from container"
docker run --rm mcr.microsoft.com/windows/nanoserver:1809 ping $pandoraFqdn
Write-Title 'Network configuration from pod'
kubectl run -it --rm --restart=Never summary --image=mcr.microsoft.com/windows/nanoserver:1809 -- ipconfig /all
Write-Title 'Network routing table from pod'
kubectl run -it --rm --restart=Never summary --image=mcr.microsoft.com/windows/nanoserver:1809 -- route print
Write-Title "Ping $pandoraFqdn from pod"
kubectl run -it --rm --restart=Never summary --image=mcr.microsoft.com/windows/nanoserver:1809 -- ping $pandoraFqdn
Write-Title 'Ping kubernetes.default from pod'
kubectl run -it --rm --restart=Never summary --image=mcr.microsoft.com/windows/nanoserver:1809 -- ping kubernetes.default
