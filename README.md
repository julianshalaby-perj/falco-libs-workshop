# Falco libs workshop · BSides Atlanta

Build a barebones C++ syscall collector with libscap and libsinsp.
Follow along or watch the presenter. The collector runs inside an Ubuntu VM.

**[Download the workshop slides](https://github.com/julianshalaby-perj/falco-libs-workshop/raw/refs/heads/main/presentation/falco-libs-intro.pptx)**

## Mac

Open Terminal, clone the repo, and set up the VM:

```sh
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
bash scripts/mac/setup.sh
```

During the workshop, run each step from this same **Mac terminal**, one at a time:

```sh
bash scripts/mac/step-1.sh
bash scripts/mac/step-2.sh
bash scripts/mac/step-3.sh
```

## Windows

Open PowerShell, clone the repo, and set up the VM:

```powershell
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
powershell -ExecutionPolicy Bypass -File scripts/windows/setup.ps1
```

During the workshop, run each step from this same **Windows PowerShell terminal**,
one at a time:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows/step-1.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-2.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-3.ps1
```

Setup offers to install Multipass, creates the VM, installs dependencies, and
builds the starter. Approve installer prompts. If Windows requests a restart,
reboot and rerun setup. Rerunning setup preserves existing source edits in the VM.

## Workshop flow

Keep terminal A on your Mac or Windows host for running your platform's scripts.
Open a second terminal, B, and enter Ubuntu:

```sh
multipass shell falco-lab
cd ~/falco-libs-workshop
```

Start with step 0 in terminal B:

```sh
sudo ./build/bin/workshop-agent
```

The starter attaches to the kernel, then waits for Enter to stop. It does not
read events yet. Press Enter before moving to step 1.

Then run your platform's step scripts in terminal A. Each script sends the complete
next version of the collector to Ubuntu, replaces `src/main.cpp` **inside the VM**,
rebuilds, and runs it for ten seconds. The host copy of `src/main.cpp` stays the
starter. The source is embedded in each script, with comment blocks marking the
additions. No manual copying, editing, or VM shell switching is needed in A.

| Step | What it adds |
| --- | --- |
| 1 | Read events for ten seconds and print a count |
| 2 | Filter to process execution exit events |
| 3 | Print the PID and process name for each execution |

Wait for “Attached to the Ubuntu kernel” in A, then run `/usr/bin/id` in B.
Wait for capture to stop before starting the next step. Each script includes
all earlier changes, so you can repeat a step or jump directly to step 3.
It replaces any edits to the VM's `src/main.cpp`.

Step 1 also sees background activity. Step 2 filters the events returned to the
application; libsinsp still processes the underlying events it needs for state.
Step 3 prints lines such as `execve pid=1234 name=id`. PIDs and counts will vary.
After any step, `cat src/main.cpp` **in B** shows the resulting collector.

| Folder | Contents |
| --- | --- |
| `presentation/` | Slides and presenter notes |
| `src/` | The starter and CMake configuration |
| `scripts/mac/` | Mac setup and steps 1–3 |
| `scripts/windows/` | Windows setup and steps 1–3 |

Stop the VM afterward with `multipass stop falco-lab` from your host terminal.

The collector monitors the Ubuntu VM's kernel, not your Mac or Windows host.
It uses libsinsp over libscap's modern eBPF engine. It does not load Falco rules.
The starter attaches without draining events, so it is only a brief first step.
The next step adds the read loop. This is a teaching example, not a production agent.

Mac step scripts have been checked against a Mac-hosted Ubuntu 24.04 arm64 VM.
Both platforms embed the same Ubuntu code. Windows scripts still need a native
Windows rehearsal.

First setup downloads the latest code from Falco’s default branch into `.deps/`.
Rerunning setup reuses that checkout. Dependencies retain their upstream licenses.
No node-agent code is vendored.

[Upstream Falco libs](https://github.com/falcosecurity/libs)
