# Falco libs workshop · BSides Atlanta

Build a barebones C++ syscall collector with libscap and libsinsp.
Follow along or watch the presenter. Use one terminal on your Mac or Windows
laptop for the entire workshop. The scripts handle Ubuntu automatically.

**[Download the workshop slides](https://github.com/julianshalaby-perj/falco-libs-workshop/raw/refs/heads/main/presentation/falco-libs-intro.pptx)**

## Mac

Open Terminal, clone the repo, and prepare the VM and libraries:

```sh
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
bash scripts/mac/setup.sh
```

Run a step, then rebuild and capture with `run`:

```sh
bash scripts/mac/step-1.sh
bash scripts/mac/run.sh
bash scripts/mac/step-2.sh
bash scripts/mac/run.sh
bash scripts/mac/step-3.sh
bash scripts/mac/run.sh
```

## Windows

Open PowerShell, clone the repo, and prepare the VM and libraries:

```powershell
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
powershell -ExecutionPolicy Bypass -File scripts/windows/setup.ps1
```

Run a step, then rebuild and capture with `run`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows/step-1.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/run.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-2.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/run.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-3.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/run.ps1
```

Setup offers to install Multipass, creates Ubuntu, installs dependencies, and
builds the Falco libraries. Approve installer prompts. If Windows requests a
restart, reboot and rerun setup.

## Workshop flow

The repo starts without collector source files. **Step 1 creates `src/` with
`main.cpp` and `CMakeLists.txt` on your laptop.** Every step writes the complete
source for that stage. Comments mark the additions. You can inspect or edit the
files locally. Rerunning a step replaces those two files.

**`run` rebuilds, generates example activity inside Ubuntu, and runs the agent
for ten seconds.** Each run creates a matching pair of files in `logs/`:

| File | Contents |
| --- | --- |
| `<run-id>.log` | Build and capture status, event count, and errors |
| `<run-id>.jsonl` | One JSON object per captured event |

The run ID contains the UTC time and runner process ID. Earlier runs are kept.
The terminal shows high-level progress and the two file paths. The runner
transfers completed files from Ubuntu, so bulk syscall output does not pass
through the terminal. You do not need to enter the VM. Successful builds stay
quiet. If a build fails, the agent does not run.

The agent stops after capture. The VM stays available for the next step.
Running `run` before step 1 explains that there is no agent and nothing to collect.

| Stage | What you see when you run |
| --- | --- |
| Before step 1 | No agent yet; nothing to collect |
| Step 1 | Attached only; the JSONL file is empty |
| Step 2 | JSONL records with event name and timestamp; count in the status log |
| Step 3 | The same JSONL records, enriched with PID and process name when available |

Wait for a run to finish, then apply the next step and run again. Every step
includes the earlier code, so you can repeat a step or skip ahead.

Step 2 reads events into user space and writes JSONL records for common
syscalls such as file opens, reads, writes, and process executions. Step 3 adds PID and process name when available. Events without
process context still appear, without the enrichment fields. Counts and PIDs vary with activity in the VM.

| Folder | Contents |
| --- | --- |
| `presentation/` | Slides and presenter notes |
| `scripts/mac/` | Mac setup, steps 1–3, run, and teardown |
| `scripts/windows/` | Windows setup, steps 1–3, run, and teardown |
| `src/` | Created by step 1, then updated by later steps |
| `logs/` | A status log and syscall JSONL file for each run |

## When you are done

Run teardown from the same host terminal:

```sh
# Mac
bash scripts/mac/teardown.sh
```

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File scripts/windows/teardown.ps1
```

Confirm with `y` to permanently delete the `falco-lab` VM and its disk, including
the dependencies and builds inside it. This ends anything running inside that VM.
Your local source and logs remain. Other VMs and the Multipass installation stay.
To repeat the workshop, run setup again to recreate the VM and dependencies.

## About the collector

The collector monitors the Ubuntu VM's kernel, not your Mac or Windows host.
It uses libsinsp over libscap's modern eBPF engine. The scheduler-switch
tracepoint is disabled because those events are not syscalls. Syscall capture
otherwise uses the default set.
There is no application filter or Falco rule engine. Every event returned
successfully by the library is written to JSONL, including both syscall directions when
available. This is the library's event stream, not a guarantee of every syscall
on the machine.
This is a teaching example, not a production agent.

First setup downloads the latest code from Falco’s default branch into `.deps/`
inside the VM. Rerunning setup reuses that checkout and preserves source files.
Dependencies retain their upstream licenses. No node-agent code is vendored.

The Mac setup and complete three-step sequence passed on the existing Ubuntu
VM, reusing cached Falco libraries. Each JSONL record parsed successfully, counts
matched the status logs, and the agent stopped after every run.

Earlier versions passed script parsing and source-generation checks on Windows
Server 2022 with Windows PowerShell 5.1 and PowerShell 7. The full Multipass
installation, VM launch, build, and capture flow still needs a Windows rehearsal.
A fresh build against the latest upstream libraries has not been verified.

[Upstream Falco libs](https://github.com/falcosecurity/libs)
