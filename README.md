# Falco libs workshop · BSides Atlanta

Build a barebones C++ syscall collector with libscap and libsinsp.
Follow along or watch the presenter. Use one terminal on your Mac or Windows
laptop for the entire workshop. The scripts handle Ubuntu automatically.

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

Setup offers to install Multipass, creates Ubuntu, installs the C++ build tools,
and downloads prebuilt Falco libraries for the VM's CPU architecture.
Attendees compile only the collector. Approve installer prompts. If Windows requests a
restart, reboot and rerun setup.

The bundles support Apple Silicon and Intel Macs, and Intel/AMD Windows PCs.
Multipass on Windows needs Hyper-V, or VirtualBox on Windows Home. The current
Windows Multipass installer does not support ARM PCs. Virtualization must be
enabled, and installation may need administrator access.

## Workshop flow

The repo starts without collector source files. **Step 1 creates `src/` with
`main.cpp` and `CMakeLists.txt` on your laptop.** Every step writes the complete
source for that stage. Comments mark the additions. You can inspect or edit the
files locally. Rerunning a step replaces those two files.

**`run` rebuilds, generates example activity inside Ubuntu, and runs the agent
for ten seconds.** Each stage saves a matching pair of files in `logs/`:

| File | Contents |
| --- | --- |
| `stage-1.log`, `stage-2.log`, `stage-3.log` | Runner progress and failures |
| `stage-1.jsonl`, `stage-2.jsonl`, `stage-3.jsonl` | One JSON object per captured event |

Rerunning a stage replaces that stage's files. Other stages' files stay.
Before step 1, the filenames are `stage-0.log` and `stage-0.jsonl`.
The runner reads the stage from the first comment in `src/main.cpp`.
The terminal shows high-level progress and the two file paths. The runner
transfers completed files from Ubuntu, so bulk syscall output does not pass
through the terminal. You do not need to enter the VM. Successful builds stay
quiet. If a build fails, the agent does not run.

The collector has no console logging or try/catch block. It writes events directly
to a JSONL file; the runner reports progress and transfers that file to your laptop.
The agent stops after capture. The VM stays available for the next step.
Running `run` before step 1 explains that there is no agent and nothing to collect.

| Stage | What you see when you run |
| --- | --- |
| Before step 1 | No agent yet; nothing to collect |
| Step 1 | Attached only; the JSONL file is empty |
| Step 2 | Raw event metadata, return status, and every captured parameter in JSONL |
| Step 3 | The same raw fields, plus process, user, file and socket context from libsinsp |

Wait for a run to finish, then apply the next step and run again. Every step
includes the earlier code, so you can repeat a step or skip ahead.

Step 2 reads events into user space and outputs the data available in each
captured event. It uses the libraries' native field and parameter names:

| Raw event data | JSON fields |
| --- | --- |
| Event metadata | `evt.type`, `evt.rawtime`, `evt.dir`, `evt.cpu`, `thread.tid` |
| Return status | `evt.rawres`, `evt.res`, `evt.failed` |
| Every captured parameter | `evt.rawarg.<name>`, such as `evt.rawarg.fd`, `evt.rawarg.name`, `evt.rawarg.flags`, `evt.rawarg.res` |

Parameter names vary by event. The collector loops over the event's parameters
instead of maintaining a shortlist. Values under `evt.rawarg.*` use libsinsp's
unresolved text representation, so they are JSON strings. This includes captured
socket tuples and data buffers, subject to the probe's capture limits and the
library's text rendering. It is a readable view, not a lossless binary dump.
`evt.rawtime` is the Unix timestamp in nanoseconds. `evt.rawres` is the numeric
return value; `evt.res` and `evt.failed` describe that value without needing
process or descriptor history.

Step 3 keeps all those fields and adds context resolved from libsinsp's state:

| Enrichment | Additional JSON fields |
| --- | --- |
| Process | `proc.pid`, `proc.name`, `proc.exepath`, `proc.cmdline`, `proc.cwd` |
| Parent | `proc.ppid`, `proc.pname` |
| User | `user.uid`, `user.name` |
| File or socket | `fd.num`, `fd.name`, `fd.type` |
| Network | `fd.lip`, `fd.lport`, `fd.rip`, `fd.rport` |

For example, a read event contains a descriptor number. Stage 3 adds the file
path associated with that descriptor. A syscall carries a thread ID; Stage 3
adds its process and command line. Some events also carry process or socket
information as raw parameters; the enrichment fields provide context across
events using libsinsp's tracked state and system information.

Both stages use libsinsp to read and parse events. Stage 3 adds only field names
to the output list, not a separate processing pass. The library extracts the
named fields with their native JSON types; unavailable values are `null`.
JsonCpp escapes the output and writes one record per line. Counts and available
values vary with activity in the VM.

| Folder | Contents |
| --- | --- |
| `scripts/mac/` | Mac setup, steps 1–3, run, and teardown |
| `scripts/windows/` | Windows setup, steps 1–3, run, and teardown |
| `src/` | Created by step 1, then updated by later steps |
| `logs/` | A status log and syscall JSONL file for each stage |

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

Setup downloads the architecture-matched Ubuntu 24.04 bundle into `.deps/falco-libs/`
inside the VM and verifies its SHA-256 checksum. Rerunning setup reuses that
bundle and preserves source files. Both architectures use the same Falco source
revision, recorded in the bundle's `manifest.json`. Upstream licenses ship in
the bundle. No node-agent code is vendored.

Both bundles passed native Ubuntu 24.04 builds and live capture for all three
stages after relocation. The ARM64 bundle also passed all stages in a fresh
2 GB Multipass VM on Mac. Downloading and unpacking the released bundle took
about two seconds on the test connection, after Ubuntu and the compiler were
already installed. First-time VM and compiler installation still take extra time.
New workshop VMs use two CPUs, 2 GB RAM, and a 12 GB disk.

Earlier versions passed script parsing and source-generation checks on Windows
Server 2022 with Windows PowerShell 5.1 and PowerShell 7. The full Multipass
installation, VM launch, build, and capture flow still needs a Windows rehearsal.

[Upstream Falco libs](https://github.com/falcosecurity/libs)
