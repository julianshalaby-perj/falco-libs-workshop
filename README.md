# Falco libs workshop · BSides Atlanta

Build a minimal C++ syscall collector with libscap and libsinsp. Follow along
from one terminal on your laptop. Capture runs inside an Ubuntu VM.

```sh
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
```

Run scripts from the repo root. Replace `<name>` with a script base name below:

| Platform | Command |
| --- | --- |
| Mac | `bash scripts/mac/<name>.sh` |
| Windows (PowerShell) | `powershell -ExecutionPolicy Bypass -File scripts/windows/<name>.ps1` |

Run this sequence, waiting for each command to finish:

```text
setup
step-1
run
step-2
run
step-3
run
teardown
```

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
