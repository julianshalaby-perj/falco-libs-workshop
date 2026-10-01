#!/usr/bin/env bash
set -euo pipefail

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
multipass exec falco-lab -- bash -s <<'UBUNTU_STEP'
set -euo pipefail
root_dir=/home/ubuntu/falco-libs-workshop
if [[ ! -f "$root_dir/build/CMakeCache.txt" ]]; then
    echo 'Run setup from your Mac or Windows folder first.' >&2
    exit 1
fi

# Replace the complete source so this step also works on its own.
cat > "$root_dir/src/main.cpp" <<'COLLECTOR_CPP'
// Step 2: filter to process executions. Earlier steps are included.
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

        /* STEP 2 ADDED: return only process execution exit events. */
        inspector.set_filter("evt.type in (execve, execveat) and evt.dir=<");
        /* END STEP 2 */

        inspector.open_modern_bpf();
        inspector.start_capture();
        std::cout << "Attached to the Ubuntu kernel." << std::endl;

        /* STEP 1 ADDED: read events for ten seconds and count them. */
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
        /* END STEP 1 */

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

echo 'Step 2: Filter to process executions. Building, then capturing for ten seconds.'
cmake --build "$root_dir/build" --target workshop-agent -j 1
sudo "$root_dir/build/bin/workshop-agent"

# End of step.
UBUNTU_STEP
