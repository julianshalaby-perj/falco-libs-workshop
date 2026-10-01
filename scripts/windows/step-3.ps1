$ErrorActionPreference = 'Stop'
$WorkshopRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Each step writes the complete source, so you can repeat it or skip ahead.
$SourceDir = Join-Path $WorkshopRoot 'src'
New-Item -ItemType Directory -Path $SourceDir -Force | Out-Null
$CMake = @'
# Loaded inside the Falco libs example tree, like node-agent.
add_executable(workshop-agent main.cpp)
target_compile_features(workshop-agent PRIVATE cxx_std_17)
target_link_libraries(workshop-agent sinsp)
set_target_properties(workshop-agent PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
'@
$Source = @'
// Step 3: add process names and pids. Earlier steps are included.
#include <chrono>
#include <cstdint>
#include <iostream>
#include <stdexcept>

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
        std::cout << "Attached to the Ubuntu kernel." << std::endl;

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

            /* STEP 3 ADDED: extend the event output with process context. */
            std::cout << event->get_name();
            const auto* process = event->get_thread_info();
            if(process != nullptr) {
                std::cout << " pid=" << process->m_pid
                          << " name=" << process->m_comm;
            }
            std::cout << '\n';
            /* END STEP 3 */
        }
        std::cout << "Read " << received << " events into user space." << std::endl;
        /* END STEP 2 */

        inspector.stop_capture();
        inspector.close();
        std::cout << "Capture stopped." << std::endl;
        return 0;
    } catch(const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
    }
}
'@
[IO.File]::WriteAllText((Join-Path $SourceDir 'CMakeLists.txt'), $CMake.Replace("`r", '') + "`n")
[IO.File]::WriteAllText((Join-Path $SourceDir 'main.cpp'), $Source.Replace("`r", '') + "`n")

Write-Host 'Step 3 source ready. Run scripts/windows/run.ps1.'
