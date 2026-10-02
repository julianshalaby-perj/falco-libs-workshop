#!/usr/bin/env bash
set -euo pipefail
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

# Each step writes main.cpp and copies the shared CMake configuration, so you can repeat it or skip ahead.
mkdir -p "$root_dir/src"
cp "$root_dir/scripts/CMakeLists.txt" "$root_dir/src/CMakeLists.txt"
cat > "$root_dir/src/main.cpp" <<'COLLECTOR_CPP'
// Step 1: create the barebones collector and attach to the Ubuntu kernel.
#include <chrono>
#include <iostream>
#include <thread>

#include <libscap/scap.h>
#include <libsinsp/sinsp.h>

int main() {
    /* STEP 1 ADDED: attach for ten seconds without reading events yet. */
    sinsp inspector;
    inspector.open_modern_bpf();
    // Scheduler switches are not syscalls; do not collect that tracepoint.
    inspector.mark_ppm_sc_of_interest(PPM_SC_SCHED_SWITCH, false);
    inspector.start_capture();
    std::this_thread::sleep_for(std::chrono::seconds(10));
    inspector.stop_capture();
    scap_stats stats{};
    inspector.get_capture_stats(&stats);
    std::cerr << "Capture engine: " << stats.n_evts << " events, "
              << stats.n_drops << " dropped; 0 read.\n";
    inspector.close();
    return 0;
}
COLLECTOR_CPP

echo 'Step 1 source ready. Run bash scripts/mac/run.sh.'
