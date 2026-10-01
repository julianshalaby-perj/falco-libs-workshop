#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
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
    multipass launch 24.04 --name falco-lab --cpus 4 --memory 8G --disk 30G
fi
multipass exec falco-lab -- mkdir -p /home/ubuntu/falco-libs-workshop
# Keep attendees' source edits when setup is run again.
if ! multipass exec falco-lab -- test -f /home/ubuntu/falco-libs-workshop/src/main.cpp; then
    multipass transfer --recursive "$root_dir/src" falco-lab:/home/ubuntu/falco-libs-workshop/
fi
multipass transfer --recursive "$root_dir/steps" "$root_dir/FALCO_LIBS_REF" \
    falco-lab:/home/ubuntu/falco-libs-workshop/
multipass exec falco-lab -- bash -s <<'UBUNTU_SETUP'
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
UBUNTU_SETUP
echo 'Enter the workshop VM: multipass shell falco-lab'
