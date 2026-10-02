#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
stage=0
if [[ -f "$root_dir/src/main.cpp" ]]; then
    stage=$(sed -n '1s|^// Step \([123]\):.*|\1|p' "$root_dir/src/main.cpp")
    if [[ -z "$stage" ]]; then
        echo 'Cannot identify the stage. Keep the first // Step N: comment in src/main.cpp.' >&2
        exit 1
    fi
fi
mkdir -p "$root_dir/logs"
run_log="$root_dir/logs/stage-$stage.log"
jsonl_file="$root_dir/logs/stage-$stage.jsonl"
: > "$run_log"
: > "$jsonl_file"

log_status() {
    printf '%s\n' "$*"
    printf '%s\n' "$*" >> "$run_log"
}
trap 'result=$?; if [[ $result -ne 0 ]]; then log_status "Run failed (exit $result)."; fi' EXIT
log_status "Stage: $stage"
if [[ $(uname -s) != Darwin ]]; then
    echo 'Run this script from your Mac terminal. Windows scripts are in scripts/windows/.' >&2
    exit 1
fi
if [[ ! -f "$root_dir/src/main.cpp" || ! -f "$root_dir/src/CMakeLists.txt" ]]; then
    log_status 'No agent yet. Nothing to collect. Run bash scripts/mac/step-1.sh first.'
    log_status "Status log: $run_log"
    log_status "Syscalls: $jsonl_file"
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
log_status 'Rebuilding the agent in Ubuntu...'
multipass exec falco-lab -- bash -s <<'UBUNTU_BUILD'
set -euo pipefail
cd /home/ubuntu/falco-libs-workshop
mkdir -p build
# CMake downloads the prebuilt libraries if needed; only main.cpp is compiled.
(
cmake -S src -B build/collector -DCMAKE_BUILD_TYPE=Release &&
cmake --build build/collector --parallel 1
) > build/workshop-build.log 2>&1 || {
    cat build/workshop-build.log >&2
    exit 1
}
# End of build.
UBUNTU_BUILD

log_status 'Build complete.'
log_status 'Running for ten seconds. Example activity is generated automatically...'
capture_result=0
multipass exec falco-lab -- bash -s <<'UBUNTU_CAPTURE' || capture_result=$?
set -euo pipefail
cd /home/ubuntu/falco-libs-workshop/build
: > workshop-syscalls.jsonl
sudo ./collector/workshop-agent > /dev/null 2> workshop-capture.log &
agent_pid=$!
# Stop this run's agent if the runner is interrupted.
trap 'kill "$agent_pid" 2>/dev/null || true' EXIT
trap 'exit 130' HUP INT TERM

# Generate activity while the agent runs, without relying on collector messages.
for attempt in {1..20}; do
    if ! kill -0 "$agent_pid" 2>/dev/null; then break; fi
    /usr/bin/id >/dev/null
    sleep 1
done
result=0
wait "$agent_pid" || result=$?
trap - EXIT HUP INT TERM
exit "$result"
# End of capture.
UBUNTU_CAPTURE
# Transfer the completed file instead of piping bulk output through exec.
multipass transfer falco-lab:/home/ubuntu/falco-libs-workshop/build/workshop-capture.log "$run_log.capture"
while IFS= read -r line || [[ -n "$line" ]]; do log_status "$line"; done < "$run_log.capture"
rm -- "$run_log.capture"
multipass transfer falco-lab:/home/ubuntu/falco-libs-workshop/build/workshop-syscalls.jsonl "$jsonl_file"
log_status "Status log: $run_log"
log_status "Syscalls: $jsonl_file"
exit "$capture_result"
