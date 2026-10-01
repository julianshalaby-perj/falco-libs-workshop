$ErrorActionPreference = 'Stop'
$WorkshopRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$MultipassBin = Join-Path $env:ProgramFiles 'Multipass\bin'
if (Test-Path $MultipassBin) { $env:Path += ";$MultipassBin" }
if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    throw 'Run scripts/windows/setup.ps1 first.'
}
& multipass start falco-lab
if ($LASTEXITCODE -ne 0) { throw 'Could not start falco-lab. Run setup first.' }
& multipass exec falco-lab -- test -f /home/ubuntu/falco-libs-workshop/build/CMakeCache.txt
if ($LASTEXITCODE -ne 0) { throw 'Run scripts/windows/setup.ps1 first.' }

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
'@
[IO.File]::WriteAllText((Join-Path $SourceDir 'CMakeLists.txt'), $CMake.Replace("`r", '') + "`n")
[IO.File]::WriteAllText((Join-Path $SourceDir 'main.cpp'), $Source.Replace("`r", '') + "`n")

& multipass exec falco-lab -- mkdir -p /home/ubuntu/falco-libs-workshop/src
if ($LASTEXITCODE -ne 0) { throw 'Could not create the source folder in Ubuntu.' }
& multipass transfer (Join-Path $SourceDir 'main.cpp') (Join-Path $SourceDir 'CMakeLists.txt') falco-lab:/home/ubuntu/falco-libs-workshop/src/
if ($LASTEXITCODE -ne 0) { throw 'Could not copy the source into Ubuntu.' }
Write-Host 'Step 3: Filter process executions. Building and running in Ubuntu.'
$UbuntuStep = @'
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
'@
$UbuntuStep.Replace("`r", '') | & multipass exec falco-lab -- bash -s
if ($LASTEXITCODE -ne 0) {
    throw "Step failed inside Ubuntu (exit $LASTEXITCODE)."
}
