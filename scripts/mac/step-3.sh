#!/usr/bin/env bash
set -euo pipefail
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

# Each step writes the complete source, so you can repeat it or skip ahead.
mkdir -p "$root_dir/src"
cat > "$root_dir/src/CMakeLists.txt" <<'COLLECTOR_CMAKE'
# Loaded inside the Falco libs example tree, like node-agent.
add_executable(workshop-agent main.cpp)
target_compile_features(workshop-agent PRIVATE cxx_std_17)
target_link_libraries(workshop-agent sinsp)
set_target_properties(workshop-agent PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
COLLECTOR_CMAKE
cat > "$root_dir/src/main.cpp" <<'COLLECTOR_CPP'
// Step 3: add process names and pids. Earlier steps are included.
#include <chrono>
#include <cstdint>
#include <iostream>
#include <stdexcept>

#include <json/json.h>
#include <libscap/scap.h>
#include <libsinsp/sinsp.h>
#include <libsinsp/threadinfo.h>

int main() {
    try {
        sinsp inspector;

        inspector.open_modern_bpf();
        // Scheduler switches are not syscalls; do not collect that tracepoint.
        inspector.mark_ppm_sc_of_interest(PPM_SC_SCHED_SWITCH, false);
        inspector.start_capture();
        std::cerr << "Attached to the Ubuntu kernel." << std::endl;

        /* STEP 2 ADDED: read and print events for ten seconds. */
        Json::StreamWriterBuilder json;
        json["indentation"] = ""; // One JSON object per line.
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

            Json::Value record;
            record["event"] = event->get_name();
            record["timestamp_ns"] = Json::UInt64(event->get_ts());

            /* STEP 3 ADDED: enrich the JSON record with process context. */
            const auto* process = event->get_thread_info();
            if(process != nullptr) {
                record["pid"] = Json::Int64(process->m_pid);
                record["name"] = process->m_comm;
            }
            /* END STEP 3 */
            std::cout << Json::writeString(json, record) << '\n';
        }
        std::cerr << "Read " << received << " events into user space." << std::endl;
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

echo 'Step 3 source ready. Run bash scripts/mac/run.sh.'
