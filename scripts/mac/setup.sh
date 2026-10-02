#!/usr/bin/env bash
set -euo pipefail

if (( EUID == 0 )); then
    echo 'Run setup as your regular user, without sudo.' >&2
    exit 1
fi

if [[ $(uname -s) != Darwin ]]; then
    echo "Run scripts/mac/setup.sh on your Mac. On Windows, use scripts/windows/setup.ps1." >&2
    exit 1
fi

export PATH="/usr/local/bin:$PATH"
if ! command -v multipass >/dev/null; then
    read -r -p 'Multipass is missing. Download and install it from Canonical? [y/N] ' install_answer
    case "$install_answer" in
        y|Y|yes|YES) ;;
        *) echo 'Setup stopped. Multipass was not installed.'; exit 1 ;;
    esac
    installer_dir=$(mktemp -d)
    trap 'rm -rf -- "$installer_dir"' EXIT
    installer_pkg="$installer_dir/multipass.pkg"
    curl --fail --location --retry 3 \
        'https://github.com/canonical/multipass/releases/download/v1.16.4/multipass-1.16.4%2Bmac-Darwin.pkg' \
        --output "$installer_pkg"
    printf '%s  %s\n' \
        'e481704f65bc1650ae8aa5c873eb9137e8b9b403eac60aa603b68d8b4d2c281c' "$installer_pkg" \
        | shasum -a 256 -c -
    sudo /usr/sbin/installer -pkg "$installer_pkg" -target /
    hash -r
    if ! command -v multipass >/dev/null; then
        echo 'Multipass installation did not provide its CLI. Rerun setup after checking the installer output.' >&2
        exit 1
    fi
fi
# Allow the newly installed daemon to start before creating the VM.
for attempt in {1..20}; do
    if multipass list >/dev/null 2>&1; then break; fi
    sleep 2
done
multipass list >/dev/null
if multipass info falco-lab >/dev/null 2>&1; then
    multipass start falco-lab
else
    echo 'Waiting for the Ubuntu 24.04 image catalog...'
    for attempt in {1..30}; do
        if multipass find release:24.04 >/dev/null 2>&1; then break; fi
        sleep 2
    done
    if ! multipass find release:24.04 >/dev/null; then
        echo 'Ubuntu image catalog is still unavailable. Rerun setup in a moment.' >&2
        exit 1
    fi
    multipass launch 24.04 --name falco-lab --cpus 2 --memory 2G --disk 12G
fi
multipass exec falco-lab -- mkdir -p /home/ubuntu/falco-libs-workshop
multipass exec falco-lab -- bash -s <<'UBUNTU_SETUP'
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
UBUNTU_SETUP
echo 'Stay in this terminal. Next: bash scripts/mac/step-1.sh'
