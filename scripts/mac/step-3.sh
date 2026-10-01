#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
if [[ $(uname -s) != Darwin ]]; then
    echo 'Run this script from your Mac terminal. Windows scripts are in scripts/windows/.' >&2
    exit 1
fi
export PATH="/usr/local/bin:$PATH"
if ! command -v multipass >/dev/null; then
    echo 'Run bash scripts/mac/setup.sh first.' >&2
    exit 1
fi
multipass start falco-lab
multipass exec falco-lab -- test -f /home/ubuntu/falco-libs-workshop/build/CMakeCache.txt

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
// Step 3: filter to process executions. Earlier steps are included.
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

        /* STEP 3 ADDED: return only process execution exit events. */
        inspector.set_filter("evt.type in (execve, execveat) and evt.dir=<");
        /* END STEP 3 */

        inspector.open_modern_bpf();
        inspector.start_capture();
        std::cout << "Attached to the Ubuntu kernel." << std::endl;

        /* STEP 2 ADDED: read events for ten seconds and count them. */
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
        }
        std::cout << "Received " << received << " events." << std::endl;
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
COLLECTOR_CPP

multipass exec falco-lab -- mkdir -p /home/ubuntu/falco-libs-workshop/src
multipass transfer "$root_dir/src/main.cpp" "$root_dir/src/CMakeLists.txt" falco-lab:/home/ubuntu/falco-libs-workshop/src/
echo 'Step 3: Filter process executions. Building and running in Ubuntu.'
multipass exec falco-lab -- bash -s <<'UBUNTU_STEP'
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
sudo "$root_dir/build/bin/workshop-agent"
# End of step.
UBUNTU_STEP
