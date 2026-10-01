$ErrorActionPreference = 'Stop'
$WorkshopRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SourceDir = Join-Path $WorkshopRoot 'src'
$LogDir = Join-Path $WorkshopRoot 'logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$RunId = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + "-$PID"
$LogFile = Join-Path $LogDir "$RunId.log"
$JsonlFile = Join-Path $LogDir "$RunId.jsonl"
[IO.File]::WriteAllText($LogFile, '')
[IO.File]::WriteAllText($JsonlFile, '')

function Write-Status {
    param([string]$Message)
    Write-Host $Message
    Add-Content -LiteralPath $LogFile -Value $Message -Encoding UTF8
}
try {
Write-Status "Run: $RunId"
if (-not (Test-Path (Join-Path $SourceDir 'main.cpp')) -or -not (Test-Path (Join-Path $SourceDir 'CMakeLists.txt'))) {
    Write-Status 'No agent yet. Nothing to collect. Run scripts/windows/step-1.ps1 first.'
    Write-Status "Status log: $LogFile"
    Write-Status "Syscalls: $JsonlFile"
    exit 0
}
$MultipassBin = Join-Path $env:ProgramFiles 'Multipass\bin'
if (Test-Path $MultipassBin) { $env:Path += ";$MultipassBin" }
if (-not (Get-Command multipass -ErrorAction SilentlyContinue)) {
    throw 'Run scripts/windows/setup.ps1 first.'
}
& multipass start falco-lab
if ($LASTEXITCODE -ne 0) { throw 'Could not start falco-lab. Run setup first.' }
& multipass exec falco-lab -- mkdir -p /home/ubuntu/falco-libs-workshop/src
if ($LASTEXITCODE -ne 0) { throw 'Could not create the source folder in Ubuntu.' }
& multipass transfer (Join-Path $SourceDir 'main.cpp') (Join-Path $SourceDir 'CMakeLists.txt') falco-lab:/home/ubuntu/falco-libs-workshop/src/
if ($LASTEXITCODE -ne 0) { throw 'Could not copy the source into Ubuntu.' }
Write-Status 'Rebuilding the agent in Ubuntu...'
$UbuntuBuild = @'
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
# Keep successful build output out of the workshop terminal.
(
cmake -S "$libs_dir" -B "$root_dir/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_BUNDLED_DEPS=ON \
    -DBUILD_LIBSCAP_MODERN_BPF=ON \
    -DCREATE_TEST_TARGETS=OFF \
    -DBUILD_LIBSINSP_EXAMPLES=ON \
    -DWORKSHOP_SOURCE_DIR="$root_dir/src" &&
cmake --build "$root_dir/build" --target workshop-agent -j 1
) > "$root_dir/build/workshop-build.log" 2>&1 || {
    cat "$root_dir/build/workshop-build.log" >&2
    exit 1
}
# End of build.
'@
$UbuntuBuild.Replace("`r", '') | & multipass exec falco-lab -- bash -s
if ($LASTEXITCODE -ne 0) { throw "Build failed inside Ubuntu (exit $LASTEXITCODE)." }

Write-Status 'Build complete.'
Write-Status 'Running for ten seconds. Example activity is generated automatically...'
$UbuntuCapture = @'
set -euo pipefail
root_dir=/home/ubuntu/falco-libs-workshop
capture_log="$root_dir/build/workshop-capture.log"
sudo "$root_dir/build/bin/workshop-agent" > "$root_dir/build/workshop-syscalls.jsonl" 2> "$capture_log" &
agent_pid=$!
# Stop this run's agent if the runner is interrupted.
trap 'kill "$agent_pid" 2>/dev/null || true' EXIT
trap 'exit 130' HUP INT TERM

# Generate one example execution after attachment, without another terminal.
for attempt in {1..200}; do
    if grep -q 'Attached to the Ubuntu kernel.' "$capture_log"; then
        /usr/bin/id >/dev/null
        break
    fi
    if ! kill -0 "$agent_pid" 2>/dev/null; then break; fi
    sleep 0.1
done
result=0
wait "$agent_pid" || result=$?
trap - EXIT HUP INT TERM
exit "$result"
# End of capture.
'@
$UbuntuCapture.Replace("`r", '') | & multipass exec falco-lab -- bash -s
$CaptureResult = $LASTEXITCODE
# Transfer the completed file instead of piping bulk output through exec.
& multipass transfer falco-lab:/home/ubuntu/falco-libs-workshop/build/workshop-capture.log "$LogFile.capture"
if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve the capture log from Ubuntu.' }
Get-Content -LiteralPath "$LogFile.capture" | ForEach-Object { Write-Status $_ }
Remove-Item -LiteralPath "$LogFile.capture"
& multipass transfer falco-lab:/home/ubuntu/falco-libs-workshop/build/workshop-syscalls.jsonl $JsonlFile
if ($LASTEXITCODE -ne 0) { throw 'Could not retrieve the syscall JSONL from Ubuntu.' }
if ($CaptureResult -ne 0) { throw "Agent failed (exit $CaptureResult). Output: $LogFile" }
Write-Status "Status log: $LogFile"
Write-Status "Syscalls: $JsonlFile"
} catch {
    Write-Status "Run failed: $_"
    exit 1
}
