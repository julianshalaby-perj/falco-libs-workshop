$ErrorActionPreference = 'Stop'
$WorkshopRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Each step writes main.cpp and copies the shared CMake configuration, so you can repeat it or skip ahead.
$SourceDir = Join-Path $WorkshopRoot 'src'
New-Item -ItemType Directory -Path $SourceDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $WorkshopRoot 'scripts/CMakeLists.txt') -Destination (Join-Path $SourceDir 'CMakeLists.txt') -Force
$Source = @'
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
'@
[IO.File]::WriteAllText((Join-Path $SourceDir 'main.cpp'), $Source.Replace("`r", '') + "`n")

Write-Host 'Step 1 source ready. Run scripts/windows/run.ps1.'
