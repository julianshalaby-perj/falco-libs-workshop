$ErrorActionPreference = 'Stop'
$MultipassBin = Join-Path $env:ProgramFiles 'Multipass\bin'
if (Test-Path $MultipassBin) { $env:Path += ";$MultipassBin" }
if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    throw 'Run scripts/windows/setup.ps1 first.'
}
& multipass start falco-lab
if ($LASTEXITCODE -ne 0) {
    throw 'Could not start falco-lab. Run scripts/windows/setup.ps1 first.'
}

# Send the complete step to Ubuntu, including source replacement and capture.
$UbuntuStep = @'
set -euo pipefail
root_dir=/home/ubuntu/falco-libs-workshop
if [[ ! -f "$root_dir/build/CMakeCache.txt" ]]; then
    echo 'Run setup from your Mac or Windows folder first.' >&2
    exit 1
fi

# Replace the complete source so this step also works on its own.
cat > "$root_dir/src/main.cpp" <<'COLLECTOR_CPP'
// Step 1: read and count events. Earlier steps are included.
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

echo 'Step 1: Read and count events. Building, then capturing for ten seconds.'
cmake --build "$root_dir/build" --target workshop-agent -j 1
sudo "$root_dir/build/bin/workshop-agent"

# End of step.
'@
$UbuntuStep.Replace("`r", '') | & multipass exec falco-lab -- bash -s
if ($LASTEXITCODE -ne 0) {
    throw "Step failed inside Ubuntu (exit $LASTEXITCODE)."
}
