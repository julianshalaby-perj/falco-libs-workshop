# Falco libs workshop · BSides Atlanta

Build a barebones C++ syscall collector with libscap and libsinsp.
Follow along or watch the presenter. All capture runs inside an Ubuntu VM.

**[Download the workshop slides](https://github.com/julianshalaby-perj/falco-libs-workshop/raw/refs/heads/main/presentation/falco-libs-intro.pptx)**

## Optional local setup

Clone this repo, then run `bash scripts/setup-mac.sh` on Mac or
`powershell -ExecutionPolicy Bypass -File scripts/setup-windows.ps1` on Windows.
Setup offers to install Multipass, creates the VM, installs dependencies, and
builds the starter. Approve the installer prompts. If Windows requests a restart,
reboot and rerun setup. Rerunning setup preserves existing source edits in the VM.

In two host terminals, enter Ubuntu:

```sh
multipass shell falco-lab
cd ~/falco-libs-workshop
```

## Build the collector one step at a time

Edit `src/main.cpp` **inside Ubuntu**. Each snippet says where it goes.

| Step | Change | What you see |
| --- | --- | --- |
| 0 | Run the starter as provided | Attached, then waits for Enter. No event reading yet. |
| 1 | Paste `snippets/01-read-events.cpp` at STEP 1 | Reads for ten seconds, then prints an event count |
| 2 | Paste `snippets/02-filter-execs.cpp` at STEP 2 | Counts only process execution exit events |
| 3 | Paste `snippets/03-process-context.cpp` at STEP 3 | Adds one line per execution with its PID and process name |

After each edit, build and run in VM terminal A:

```sh
cmake --build build --target workshop-agent -j 1
sudo ./build/bin/workshop-agent
```

For steps 1–3, run `/usr/bin/id` in VM terminal B during the ten-second capture.
Step 1 also sees background activity. Step 2 filters the events returned to the
application; libsinsp still processes the underlying events it needs for state.
Step 3 prints lines such as `execve pid=1234 name=id`. PIDs and counts will vary.

`snippets/finished.cpp` is the complete collector for reference. If you want to
skip editing, copy it to `src/main.cpp` inside the VM, then build and run.

| Folder | Contents |
| --- | --- |
| `presentation/` | Slides and presenter notes |
| `src/` | The starter and CMake configuration |
| `snippets/` | Three paste-in snippets and the finished collector |
| `scripts/` | Standalone Mac and Windows setup |

Stop the VM afterward with `multipass stop falco-lab` from your host terminal.

The collector monitors the Ubuntu VM's kernel, not your Mac or Windows host.
It uses libsinsp over libscap's modern eBPF engine. It does not load Falco rules.
The starter attaches without draining events, so it is only a brief first step.
The next step adds the read loop. This is a teaching example, not a production agent.

Checked on the Mac-hosted Ubuntu 24.04 arm64 VM: every stage compiles, the
starter attaches and stops, and the finished collector captures process executions.
Windows setup still needs a rehearsal.

`FALCO_LIBS_REF` pins the library revision. Setup downloads dependencies into
`.deps/`; they retain their upstream licenses. No node-agent code is vendored.

[Upstream Falco libs](https://github.com/falcosecurity/libs/tree/e72873882967cdd86b8753eca09ea3e9f91ccd4a)
