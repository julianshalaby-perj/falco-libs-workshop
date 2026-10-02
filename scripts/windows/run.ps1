$ErrorActionPreference = 'Stop'
$WorkshopRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SourceDir = Join-Path $WorkshopRoot 'src'
$Stage = 0
if (Test-Path (Join-Path $SourceDir 'main.cpp')) {
    $FirstLine = Get-Content -LiteralPath (Join-Path $SourceDir 'main.cpp') -TotalCount 1
    if ($FirstLine -notmatch '^// Step ([123]):') {
        throw 'Cannot identify the stage. Keep the first // Step N: comment in src/main.cpp.'
    }
    $Stage = $Matches[1]
}
$LogDir = Join-Path $WorkshopRoot 'logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir "stage-$Stage.log"
$JsonlFile = Join-Path $LogDir "stage-$Stage.jsonl"
[IO.File]::WriteAllText($LogFile, '')
[IO.File]::WriteAllText($JsonlFile, '')

function Write-Status {
    param([string]$Message)
    Write-Host $Message
    Add-Content -LiteralPath $LogFile -Value $Message -Encoding UTF8
}
try {
Write-Status "Stage: $Stage"
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
cd /home/ubuntu/falco-libs-workshop
mkdir -p build
# CMake downloads the prebuilt libraries if needed; only main.cpp is compiled.
(
cmake -S src -B build/collector -DCMAKE_BUILD_TYPE=Release &&
cmake --build build/collector --parallel 1
) > build/workshop-build.log 2>&1 || {
    cat build/workshop-build.log >&2
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
cd /home/ubuntu/falco-libs-workshop/build
: > workshop-syscalls.jsonl
sudo ./collector/workshop-agent > /dev/null 2> workshop-capture.log &
agent_pid=$!
# Stop this run's agent if the runner is interrupted.
trap 'kill "$agent_pid" 2>/dev/null || true' EXIT
trap 'exit 130' HUP INT TERM

# Generate activity while the agent runs, without relying on collector messages.
for attempt in {1..20}; do
    if ! kill -0 "$agent_pid" 2>/dev/null; then break; fi
    /usr/bin/id >/dev/null
    sleep 1
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
