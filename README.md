# Falco libs workshop · BSides Atlanta

Build a barebones C++ syscall collector with libscap and libsinsp.
Follow along or watch the presenter. All capture runs inside an Ubuntu VM.

**[Download the workshop slides](https://github.com/julianshalaby-perj/falco-libs-workshop/raw/refs/heads/main/presentation/falco-libs-intro.pptx)**

## Optional local setup

### Mac

Open Terminal:

```sh
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
bash scripts/mac/setup.sh
```

### Windows

Open PowerShell:

```powershell
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
powershell -ExecutionPolicy Bypass -File scripts/windows/setup.ps1
```

### After setup (both)

Setup offers to install Multipass, creates the VM, installs dependencies, and
builds the starter. Approve the installer prompts. If Windows requests a restart,
reboot and rerun setup. Rerunning setup preserves existing source edits in the VM.

In two host terminals, enter Ubuntu:

```sh
multipass shell falco-lab
cd ~/falco-libs-workshop
```

## Run each step

All commands below run **inside Ubuntu**. Start in terminal A:

```sh
sudo ./build/bin/workshop-agent
```

The starter attaches to the kernel, then waits for Enter to stop. It does not
read events yet. Press Enter before moving to step 1.

Each step script replaces `src/main.cpp` with its complete version, rebuilds the
collector, and runs it for ten seconds. No manual copying or editing is needed.
The source is embedded in the script, with comment blocks marking each addition.
Running a step overwrites any edits to `src/main.cpp`. Run the scripts without
sudo; they request sudo only when starting capture.

| Command in VM terminal A | What it adds |
| --- | --- |
| `bash steps/step-1.sh` | Read events for ten seconds and print a count |
| `bash steps/step-2.sh` | Filter to process execution exit events |
| `bash steps/step-3.sh` | Print the PID and process name for each execution |

Wait for “Attached to the Ubuntu kernel,” then run `/usr/bin/id` in VM terminal B.
Wait for the capture to stop before starting the next step. Each script includes
all earlier changes, so you can repeat a step or jump directly to step 3.

Step 1 also sees background activity. Step 2 filters the events returned to the
application; libsinsp still processes the underlying events it needs for state.
Step 3 prints lines such as `execve pid=1234 name=id`. PIDs and counts will vary.
After any step, `cat src/main.cpp` shows the resulting collector.

| Folder | Contents |
| --- | --- |
| `presentation/` | Slides and presenter notes |
| `src/` | The starter and CMake configuration |
| `steps/` | Three standalone scripts containing the complete code for each step |
| `scripts/mac/` | Mac setup |
| `scripts/windows/` | Windows setup |

Stop the VM afterward with `multipass stop falco-lab` from your host terminal.

The collector monitors the Ubuntu VM's kernel, not your Mac or Windows host.
It uses libsinsp over libscap's modern eBPF engine. It does not load Falco rules.
The starter attaches without draining events, so it is only a brief first step.
The next step adds the read loop. This is a teaching example, not a production agent.

All three step scripts were run successfully on a Mac-hosted Ubuntu 24.04 arm64 VM,
including rebuilding and capturing live events.
Windows setup still needs a rehearsal.

`FALCO_LIBS_REF` pins the library revision. Setup downloads dependencies into
`.deps/`; they retain their upstream licenses. No node-agent code is vendored.

[Upstream Falco libs](https://github.com/falcosecurity/libs/tree/e72873882967cdd86b8753eca09ea3e9f91ccd4a)
