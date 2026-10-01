$ErrorActionPreference = 'Stop'
$WorkshopRoot = Split-Path -Parent $PSScriptRoot

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
        'launch', '24.04', '--name', 'falco-lab', '--cpus', '4', '--memory', '8G', '--disk', '30G'
    )
}
Invoke-LabMultipass -CommandArgs @('exec', 'falco-lab', '--', 'mkdir', '-p', '/home/ubuntu/falco-libs-workshop')

# Keep attendees' source edits when setup is run again.
& multipass exec falco-lab -- test -f /home/ubuntu/falco-libs-workshop/src/main.cpp
if ($LASTEXITCODE -ne 0) {
    Invoke-LabMultipass -CommandArgs @(
        'transfer', '--recursive', (Join-Path $WorkshopRoot 'src'),
        'falco-lab:/home/ubuntu/falco-libs-workshop/'
    )
}
Invoke-LabMultipass -CommandArgs @(
    'transfer', '--recursive', (Join-Path $WorkshopRoot 'steps'),
    (Join-Path $WorkshopRoot 'FALCO_LIBS_REF'), 'falco-lab:/home/ubuntu/falco-libs-workshop/'
)
# Run the Ubuntu setup below directly inside the VM.
$UbuntuSetup = @'
set -euo pipefail
root_dir=/home/ubuntu/falco-libs-workshop
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
    echo 'This setup script targets Ubuntu 24.04.' >&2
    exit 1
fi

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential ca-certificates clang cmake git pkg-config \
    libelf-dev zlib1g-dev linux-tools-common "linux-tools-$(uname -r)" nano

printf 'Kernel: %s\nArchitecture: %s\n' "$(uname -r)" "$(uname -m)"
case $(uname -m) in
    x86_64|aarch64) ;;
    *) echo 'This workshop targets x86_64 or aarch64 Linux.' >&2; exit 1 ;;
esac
kernel_version=$(uname -r)
IFS=. read -r kernel_major kernel_minor _ <<< "$kernel_version"
if (( kernel_major < 5 || (kernel_major == 5 && kernel_minor < 8) )); then
    echo 'Modern eBPF needs kernel 5.8 or newer for this lab. Use Ubuntu 24.04.' >&2
    exit 1
fi
if [[ ! -r /sys/kernel/btf/vmlinux ]]; then
    echo 'Missing readable /sys/kernel/btf/vmlinux. Use the stock Ubuntu VM kernel.' >&2
    exit 1
fi
for tool in cmake make git g++ clang bpftool pkg-config nano; do
    if ! command -v "$tool" >/dev/null; then
        printf 'Missing %s. Rerun your setup script on the host.\n' "$tool" >&2
        exit 1
    fi
done
bpftool version
cmake --version | head -n 1
echo 'Prerequisites passed. Building the agent.'

libs_dir="$root_dir/.deps/falcosecurity-libs"
libs_ref=$(tr -d '\r\n' < "$root_dir/FALCO_LIBS_REF")
if [[ ! $libs_ref =~ ^[0-9a-f]{40}$ ]]; then
    echo 'FALCO_LIBS_REF must contain a full commit SHA.' >&2
    exit 1
fi
mkdir -p "$root_dir/.deps"
if [[ ! -d "$libs_dir/.git" ]]; then
    git init "$libs_dir"
    git -C "$libs_dir" remote add origin https://github.com/falcosecurity/libs.git
fi
if ! git -C "$libs_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$libs_dir" fetch --depth 1 origin "$libs_ref"
    git -C "$libs_dir" checkout --detach "$libs_ref"
fi
if [[ $(git -C "$libs_dir" rev-parse HEAD) != "$libs_ref" ]]; then
    echo 'Dependency revision differs from FALCO_LIBS_REF. Move .deps/ and build/ aside and rebuild.' >&2
    exit 1
fi

# Same integration point as node-agent. Keep our source in place so edits rebuild
# only the agent. Appending this once also makes reruns independent of internet.
examples="$libs_dir/userspace/libsinsp/examples/CMakeLists.txt"
entry='add_subdirectory("${WORKSHOP_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/workshop")'
if ! grep -Fqx "$entry" "$examples"; then
    printf '\n%s\n' "$entry" >> "$examples"
fi
cmake -S "$libs_dir" -B "$root_dir/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_BUNDLED_DEPS=ON \
    -DBUILD_LIBSCAP_MODERN_BPF=ON \
    -DCREATE_TEST_TARGETS=OFF \
    -DWORKSHOP_SOURCE_DIR="$root_dir/src"
# Keep memory use predictable on laptops. Set BUILD_JOBS=2 if the VM has room.
cmake --build "$root_dir/build" --target workshop-agent --parallel "${BUILD_JOBS:-1}"
printf '\nBuilt: %s/build/bin/workshop-agent\n' "$root_dir"

echo 'Setup complete. Enter the VM, then run sudo ./build/bin/workshop-agent.'
# End of Ubuntu setup.
'@
$UbuntuSetup.Replace("`r", '') | & multipass exec falco-lab -- bash -s
if ($LASTEXITCODE -ne 0) {
    throw "Ubuntu setup failed (exit $LASTEXITCODE)."
}
Write-Host 'Enter the workshop VM: multipass shell falco-lab'
