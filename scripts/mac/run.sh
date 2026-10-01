#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ $(uname -s) != Darwin ]]; then
    echo 'Run this script from your Mac terminal. Windows scripts are in scripts/windows/.' >&2
    exit 1
fi
if [[ ! -f "$root_dir/src/main.cpp" || ! -f "$root_dir/src/CMakeLists.txt" ]]; then
    echo 'No agent yet. Nothing to collect. Run bash scripts/mac/step-1.sh first.'
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
# Keep successful build output out of the workshop terminal.
(
cmake -S "$libs_dir" -B "$root_dir/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_BUNDLED_DEPS=ON \
    -DBUILD_LIBSCAP_MODERN_BPF=ON \
    -DCREATE_TEST_TARGETS=OFF \
    -DBUILD_LIBSINSP_EXAMPLES=ON \
    -DWORKSHOP_SOURCE_DIR="$root_dir/src" &&
cmake --build "$root_dir/build" --target workshop-agent -j 1
) > "$root_dir/build/workshop-build.log" 2>&1 || {
    cat "$root_dir/build/workshop-build.log" >&2
    exit 1
}
# End of build.
UBUNTU_BUILD

mkdir -p "$root_dir/logs"
echo 'Running for ten seconds. Example activity is generated automatically...'
capture_result=0
multipass exec falco-lab -- bash -s <<'UBUNTU_CAPTURE' || capture_result=$?
set -euo pipefail
root_dir=/home/ubuntu/falco-libs-workshop
capture_log="$root_dir/build/workshop-capture.log"
sudo "$root_dir/build/bin/workshop-agent" > "$capture_log" 2>&1 &
agent_pid=$!
# Stop this run's agent if the runner is interrupted.
trap 'kill "$agent_pid" 2>/dev/null || true' EXIT
trap 'exit 130' HUP INT TERM

# Generate one example execution after attachment, without another terminal.
for attempt in {1..200}; do
    if grep -q 'Attached to the Ubuntu kernel.' "$capture_log"; then
        /usr/bin/id >/dev/null
        break
    fi
    if ! kill -0 "$agent_pid" 2>/dev/null; then break; fi
    sleep 0.1
done
result=0
wait "$agent_pid" || result=$?
trap - EXIT HUP INT TERM
exit "$result"
# End of capture.
UBUNTU_CAPTURE
# Transfer the completed file instead of piping bulk output through exec.
multipass transfer falco-lab:/home/ubuntu/falco-libs-workshop/build/workshop-capture.log "$root_dir/logs/latest.log"
cat "$root_dir/logs/latest.log"
echo "Saved output: $root_dir/logs/latest.log"
exit "$capture_result"
