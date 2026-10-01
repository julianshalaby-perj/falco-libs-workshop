#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if (( EUID == 0 )); then
    echo 'Run setup as your regular user, without sudo.' >&2
    exit 1
fi

if [[ $(uname -s) == Darwin ]]; then
    if ! command -v multipass >/dev/null; then
        echo 'Install Multipass, then rerun setup: https://canonical.com/multipass/download/macos' >&2
        exit 1
    fi
    if multipass info falco-lab >/dev/null 2>&1; then
        multipass start falco-lab
    else
        multipass launch 24.04 --name falco-lab --cpus 4 --memory 8G --disk 30G
    fi
    multipass exec falco-lab -- mkdir -p /home/ubuntu/falco-libs-workshop
    # Keep attendees' source edits when setup is run again.
    if ! multipass exec falco-lab -- test -f /home/ubuntu/falco-libs-workshop/src/main.cpp; then
        multipass transfer --recursive "$root_dir/src" falco-lab:/home/ubuntu/falco-libs-workshop/
    fi
    multipass transfer --recursive "$root_dir/scripts" "$root_dir/FALCO_LIBS_REF" \
        falco-lab:/home/ubuntu/falco-libs-workshop/
    multipass exec falco-lab -- bash /home/ubuntu/falco-libs-workshop/scripts/setup.sh
    echo 'Enter the workshop VM: multipass shell falco-lab'
    exit 0
fi

if [[ $(uname -s) != Linux ]]; then
    echo 'On Windows, run scripts/setup.ps1 from PowerShell.' >&2
    exit 1
fi
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
    echo 'This setup script targets Ubuntu 24.04.' >&2
    exit 1
fi

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential ca-certificates clang cmake git pkg-config \
    libelf-dev zlib1g-dev linux-tools-common "linux-tools-$(uname -r)" jq nano
bash "$root_dir/scripts/build.sh"
"$root_dir/build/bin/workshop-agent" --help
printf '\nSetup complete. Inside Ubuntu, run:\ncd ~/falco-libs-workshop\nsudo ./build/bin/workshop-agent\n'
