#!/usr/bin/env bash
set -euo pipefail
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

# Each step writes the complete source, so you can repeat it or skip ahead.
mkdir -p "$root_dir/src"
cat > "$root_dir/src/CMakeLists.txt" <<'COLLECTOR_CMAKE'
cmake_minimum_required(VERSION 3.16)
project(workshop-agent LANGUAGES CXX)
find_package(FalcoWorkshop CONFIG REQUIRED)
add_executable(workshop-agent main.cpp)
target_compile_features(workshop-agent PRIVATE cxx_std_17)
target_link_libraries(workshop-agent sinsp)
COLLECTOR_CMAKE
cat > "$root_dir/src/main.cpp" <<'COLLECTOR_CPP'
// Step 1: create the barebones collector and attach to the Ubuntu kernel.
#include <chrono>
#include <thread>

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
    inspector.close();
    return 0;
}
COLLECTOR_CPP

echo 'Step 1 source ready. Run bash scripts/mac/run.sh.'
