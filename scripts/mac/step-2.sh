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
set_target_properties(workshop-agent PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/../bin"
)
COLLECTOR_CMAKE
cat > "$root_dir/src/main.cpp" <<'COLLECTOR_CPP'
// Step 2: read and print events. Earlier steps are included.
#include <chrono>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>

#include <libscap/scap.h>
#include <libsinsp/sinsp.h>
#include <libsinsp/eventformatter.h>

int main() {
    try {
        sinsp inspector;
        sinsp_filter_check_list fields;
        sinsp_evt_formatter formatter(&inspector, fields);
        // The leading * keeps events even when some fields are unavailable.
        formatter.set_format(sinsp_evt_formatter::OF_JSON,
            "*%evt.type %evt.rawtime");

        inspector.open_modern_bpf();
        // Scheduler switches are not syscalls; do not collect that tracepoint.
        inspector.mark_ppm_sc_of_interest(PPM_SC_SCHED_SWITCH, false);
        inspector.start_capture();
        std::cerr << "Attached to the Ubuntu kernel." << std::endl;

        /* STEP 2 ADDED: read and print events for ten seconds. */
        std::uint64_t received = 0;
        const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(10);
        while(std::chrono::steady_clock::now() < until) {
            sinsp_evt* event = nullptr;
            const auto result = inspector.next(&event);
            if(result == SCAP_TIMEOUT || result == SCAP_FILTERED_EVENT) {
                continue;
            }
            if(result == SCAP_EOF) {
                break;
            }
            if(result != SCAP_SUCCESS) {
                throw std::runtime_error(inspector.getlasterr());
            }
            ++received;
            std::string output;
            formatter.tostring(event, output);
            std::cout << output << '\n';
        }
        std::cerr << "Read " << received << " events into user space.\n";
        /* END STEP 2 */

        inspector.stop_capture();
        inspector.close();
        std::cerr << "Capture stopped." << std::endl;
        return 0;
    } catch(const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
    }
}
COLLECTOR_CPP

echo 'Step 2 source ready. Run bash scripts/mac/run.sh.'
