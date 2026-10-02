# Falco libs workshop · BSides Atlanta

Build a minimal C++ syscall collector with libscap and libsinsp. Follow along
from one terminal on your laptop. Capture runs inside an Ubuntu VM.

## Mac

Open Terminal and run each command in order:

```sh
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
bash scripts/mac/setup.sh
bash scripts/mac/step-1.sh
bash scripts/mac/run.sh
bash scripts/mac/step-2.sh
bash scripts/mac/run.sh
bash scripts/mac/step-3.sh
bash scripts/mac/run.sh
```

When finished:

```sh
bash scripts/mac/teardown.sh
```

## Windows

Open PowerShell and run each command in order:

```powershell
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
powershell -ExecutionPolicy Bypass -File scripts/windows/setup.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-1.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/run.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-2.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/run.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-3.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/run.ps1
```

When finished:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows/teardown.ps1
```

## Workshop flow

`setup` offers to install Multipass, creates the `falco-lab` Ubuntu VM, and
installs build tools. The first `run` downloads prebuilt Falco libraries.

Each step creates `src/main.cpp` and `src/CMakeLists.txt`, replacing the previous
stage. `run` rebuilds the collector and captures for ten seconds.

| Stage | Result |
| --- | --- |
| `step-1` | Capture without reading. Log the capture count; JSONL stays empty. |
| `step-2` | Read events and write raw event fields and parameters. |
| `step-3` | Add process, user, file, and socket context from libsinsp. |

Results go to `logs/stage-N.log` and `logs/stage-N.jsonl`. Rerunning a stage
replaces its logs. The collector stops after each run; the VM stays available.

`teardown` asks for confirmation, then deletes the workshop VM and its disk.
Local source and logs remain.

Supports Intel and Apple Silicon Macs, and Intel/AMD Windows PCs. Windows
needs Hyper-V or VirtualBox; ARM Windows is unsupported. If setup requests a
restart, reboot and rerun it.

[Upstream Falco libs](https://github.com/falcosecurity/libs)
