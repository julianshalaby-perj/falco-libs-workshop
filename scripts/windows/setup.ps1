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
root_dir=/home/ubuntu/falco-libs-workshop
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
    echo 'This setup script targets Ubuntu 24.04.' >&2
    exit 1
fi
arch=$(uname -m)
case "$arch" in
    x86_64|aarch64) ;;
    *) echo "No workshop libraries are available for $arch." >&2; exit 1 ;;
esac
if [[ ! -r /sys/kernel/btf/vmlinux ]]; then
    echo 'Missing /sys/kernel/btf/vmlinux. Use the stock Ubuntu 24.04 VM kernel.' >&2
    exit 1
fi
# Attendees compile only the collector, using Ubuntu's compiler and CMake.
if ! command -v g++ >/dev/null || ! command -v cmake >/dev/null || ! command -v make >/dev/null || ! command -v curl >/dev/null; then
    sudo apt-get update
    sudo apt-get install -y --no-install-recommends build-essential ca-certificates cmake curl
fi
release=sdk-2026-10-02-v1
sdk_dir="$root_dir/.deps/falco-libs"
if [[ ! -f "$sdk_dir/.release" ]] || [[ $(cat "$sdk_dir/.release") != "$release" ]]; then
    echo "Downloading prebuilt Falco libraries for $arch..."
    mkdir -p "$root_dir/.deps"
    download_dir=$(mktemp -d "$root_dir/.deps/download.XXXXXX")
    trap 'rm -rf -- "$download_dir"' EXIT
    bundle="falco-libs-ubuntu24.04-$arch.tar.gz"
    url="https://github.com/julianshalaby-perj/falco-libs-workshop/releases/download/$release"
    curl --fail --location --retry 3 "$url/$bundle" -o "$download_dir/$bundle"
    curl --fail --location --retry 3 "$url/$bundle.sha256" -o "$download_dir/$bundle.sha256"
    (cd "$download_dir" && sha256sum -c "$bundle.sha256")
    tar -xzf "$download_dir/$bundle" -C "$download_dir"
    [[ -f "$download_dir/falco-libs/FalcoWorkshopConfig.cmake" ]]
    # Replace only our downloaded library bundle after verification succeeds.
    rm -rf -- "$sdk_dir"
    mv "$download_dir/falco-libs" "$sdk_dir"
    printf '%s\n' "$release" > "$sdk_dir/.release"
else
    echo 'Prebuilt Falco libraries are already installed.'
fi
echo 'Setup complete. No Falco library compilation needed.'
# End of Ubuntu setup.
'@
$UbuntuSetup.Replace("`r", '') | & multipass exec falco-lab -- bash -s
if ($LASTEXITCODE -ne 0) {
    throw "Ubuntu setup failed (exit $LASTEXITCODE)."
}
Write-Host 'Stay in PowerShell. Next: powershell -ExecutionPolicy Bypass -File scripts/windows/step-1.ps1'
