#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ $(uname -s) != Darwin ]]; then
    echo 'Run this script from your Mac terminal. Windows scripts are in scripts/windows/.' >&2
    exit 1
fi
if [[ ! -f "$root_dir/src/main.cpp" || ! -f "$root_dir/src/CMakeLists.txt" ]]; then
    echo 'No agent yet. Run bash scripts/mac/step-1.sh first.'
    exit 0
fi
export PATH="/usr/local/bin:$PATH"
if ! command -v multipass >/dev/null; then
    echo 'Run bash scripts/mac/setup.sh first.' >&2
    exit 1
fi
multipass start falco-lab
multipass exec falco-lab -- mkdir -p /home/ubuntu/falco-libs-workshop/src
multipass transfer "$root_dir/src/main.cpp" "$root_dir/src/CMakeLists.txt" falco-lab:/home/ubuntu/falco-libs-workshop/src/
echo 'Rebuilding the agent in Ubuntu...'
multipass exec falco-lab -- bash -s <<'UBUNTU_BUILD'
set -euo pipefail
root_dir=/home/ubuntu/falco-libs-workshop
libs_dir="$root_dir/.deps/falcosecurity-libs"
if [[ ! -f "$root_dir/build/CMakeCache.txt" ]]; then
    echo 'Run setup from your Mac or Windows folder first.' >&2
    exit 1
fi
# Build the workshop source as a Falco libs example.
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
    -DBUILD_LIBSINSP_EXAMPLES=ON \
    -DWORKSHOP_SOURCE_DIR="$root_dir/src"
cmake --build "$root_dir/build" --target workshop-agent -j 1
# End of build.
UBUNTU_BUILD

mkdir -p "$root_dir/logs"
echo 'Running the agent for ten seconds...'
multipass exec falco-lab -- bash -c 'exec sudo /home/ubuntu/falco-libs-workshop/build/bin/workshop-agent 2>&1' | tee "$root_dir/logs/latest.log"
echo "Saved output: $root_dir/logs/latest.log"
