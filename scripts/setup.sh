#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Linux ]]; then
    echo 'Run this inside the Ubuntu VM, not on macOS or Windows.' >&2
    exit 1
fi
source /etc/os-release
if [[ ${ID:-} != ubuntu || ${VERSION_ID:-} != 24.04 ]]; then
    echo 'This setup script targets Ubuntu 24.04. See pre-setup in the presentation.' >&2
    exit 1
fi

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    build-essential ca-certificates clang cmake git pkg-config \
    libelf-dev zlib1g-dev linux-tools-common "linux-tools-$(uname -r)" jq nano

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash "$root_dir/scripts/doctor.sh"
echo 'Dependencies ready. Next: bash scripts/build.sh (without sudo).'
