$ErrorActionPreference = 'Stop'

if (@(Get-CimInstance Win32_Processor).Architecture -contains 12) {
    throw 'The current Multipass Windows installer does not support ARM PCs. Use an Intel/AMD Windows laptop or a Mac for this lab.'
}
if (-not [Environment]::Is64BitProcess) {
    throw 'Open 64-bit PowerShell and run setup again.'
}

function Invoke-LabMultipass {
    param([string[]] $CommandArgs)
    & multipass @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Multipass failed (exit $LASTEXITCODE): $($CommandArgs -join ' ')"
    }
}

$MultipassBin = Join-Path $env:ProgramFiles 'Multipass\bin'
if (Test-Path $MultipassBin) { $env:Path += ";$MultipassBin" }
if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    $InstallAnswer = Read-Host 'Multipass is missing. Download and install it from Canonical? [y/N]'
    if ($InstallAnswer -notmatch '^(y|yes)$') {
        Write-Host 'Setup stopped. Multipass was not installed.'
        exit 1
    }
    $InstallerDir = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $InstallerDir | Out-Null
    try {
        $InstallerPath = Join-Path $InstallerDir 'multipass.msi'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri `
            'https://github.com/canonical/multipass/releases/download/v1.16.4/multipass-1.16.4%2Bwin-win64.msi' `
            -OutFile $InstallerPath
        $ExpectedHash = 'b0c417fb8254fa61e4aa63895f59354bb3717c58100816651a9300dd98124aea'
        if ((Get-FileHash -Algorithm SHA256 $InstallerPath).Hash -ne $ExpectedHash) {
            throw 'Multipass installer checksum did not match. Installation stopped.'
        }
        $Installer = Start-Process msiexec.exe -Verb RunAs -Wait -PassThru `
            -ArgumentList "/i `"$InstallerPath`" /norestart"
        if ($Installer.ExitCode -in @(3010, 1641)) {
            Write-Host 'Multipass installed. Restart Windows, then rerun this setup command.'
            exit 0
        }
        if ($Installer.ExitCode -ne 0) {
            throw "Multipass installation stopped (exit $($Installer.ExitCode))."
        }
    } finally {
        Remove-Item -Recurse -Force $InstallerDir
    }
    $env:Path += ";$MultipassBin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
        throw 'Multipass CLI is unavailable. Reopen PowerShell and rerun setup.'
    }
}

# Allow the newly installed daemon to start before creating the VM.
try {
    $ErrorActionPreference = 'Continue'
    for ($Attempt = 0; $Attempt -lt 20; $Attempt++) {
        & multipass list *> $null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 2
    }
} finally {
    $ErrorActionPreference = 'Stop'
}

$Instances = Invoke-LabMultipass -CommandArgs @('list', '--format', 'json') | ConvertFrom-Json
if ($Instances.list.name -contains 'falco-lab') {
    Invoke-LabMultipass -CommandArgs @('start', 'falco-lab')
} else {
    Write-Host 'Waiting for the Ubuntu 24.04 image catalog...'
    $ImageReady = $false
    try {
        $ErrorActionPreference = 'Continue'
        for ($Attempt = 0; $Attempt -lt 30; $Attempt++) {
            & multipass find release:24.04 *> $null
            if ($LASTEXITCODE -eq 0) {
                $ImageReady = $true
                break
            }
            Start-Sleep -Seconds 2
        }
    } finally {
        $ErrorActionPreference = 'Stop'
    }
    if (-not $ImageReady) {
        throw 'Ubuntu image catalog is still unavailable. Rerun setup in a moment.'
    }
    Invoke-LabMultipass -CommandArgs @(
        'launch', '24.04', '--name', 'falco-lab', '--cpus', '2', '--memory', '2G', '--disk', '12G'
    )
}
Invoke-LabMultipass -CommandArgs @('exec', 'falco-lab', '--', 'mkdir', '-p', '/home/ubuntu/falco-libs-workshop')

# Run the Ubuntu setup below directly inside the VM.
$UbuntuSetup = @'
set -euo pipefail
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
    echo 'This setup script targets Ubuntu 24.04.' >&2
    exit 1
fi
if [[ ! -r /sys/kernel/btf/vmlinux ]]; then
    echo 'Missing /sys/kernel/btf/vmlinux. Use the stock Ubuntu 24.04 VM kernel.' >&2
    exit 1
fi
# Attendees compile only the collector, using Ubuntu's compiler and CMake.
if ! command -v g++ >/dev/null || ! command -v cmake >/dev/null || ! command -v make >/dev/null; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends build-essential ca-certificates cmake
fi
echo 'Setup complete. The VM and build tools are ready.'
# End of Ubuntu setup.
'@
$UbuntuSetup.Replace("`r", '') | & multipass exec falco-lab -- bash -s
if ($LASTEXITCODE -ne 0) {
    throw "Ubuntu setup failed (exit $LASTEXITCODE)."
}
Write-Host 'Stay in PowerShell. Next: powershell -ExecutionPolicy Bypass -File scripts/windows/step-1.ps1'
