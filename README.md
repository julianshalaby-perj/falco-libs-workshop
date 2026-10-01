# Falco libs workshop · BSides Atlanta

Build a barebones C++ syscall collector with libscap and libsinsp.
Follow along or watch the presenter. The collector runs inside an Ubuntu VM.

**[Download the workshop slides](https://github.com/julianshalaby-perj/falco-libs-workshop/raw/refs/heads/main/presentation/falco-libs-intro.pptx)**

## Mac

Open Terminal, clone the repo, and prepare the VM and libraries:

```sh
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
bash scripts/mac/setup.sh
```

Run these from the same **Mac terminal**, one step at a time:

```sh
bash scripts/mac/step-1.sh
bash scripts/mac/step-2.sh
bash scripts/mac/step-3.sh
bash scripts/mac/step-4.sh
```

## Windows

Open PowerShell, clone the repo, and prepare the VM and libraries:

```powershell
git clone https://github.com/julianshalaby-perj/falco-libs-workshop.git
cd falco-libs-workshop
powershell -ExecutionPolicy Bypass -File scripts/windows/setup.ps1
```

Run these from the same **Windows PowerShell terminal**, one step at a time:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/windows/step-1.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-2.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-3.ps1
powershell -ExecutionPolicy Bypass -File scripts/windows/step-4.ps1
```

Setup offers to install Multipass, creates Ubuntu, installs dependencies, and
builds the Falco libraries. Approve installer prompts. If Windows requests a
restart, reboot and rerun setup.

## Workshop flow

The repo starts without collector source files. **Step 1 creates `src/` with
`main.cpp` and `CMakeLists.txt` on your laptop**, copies them into Ubuntu, and
builds and runs the barebones collector. It prints that it attached, then stops.
It does not read events yet.

Every step writes the complete source and CMake configuration on your laptop,
copies them into the VM, then builds and runs the collector. Comments mark each
addition. You can inspect the generated files in your local editor. Rerunning a
step replaces edits to those two files, both locally and inside the VM.

| Step | What it adds |
| --- | --- |
| 1 | Create `src/main.cpp` and `src/CMakeLists.txt`, attach, then stop |
| 2 | Read events for ten seconds and print a count |
| 3 | Filter to process execution exit events |
| 4 | Print the PID and process name for each execution |

Keep terminal A on your laptop for running the scripts. Open a second terminal,
B, and enter Ubuntu:

```sh
multipass shell falco-lab
cd ~/falco-libs-workshop
```

For steps 2–4, wait for “Attached to the Ubuntu kernel” in A, then run this in B:

```sh
/usr/bin/id
```

Each capture stops after ten seconds. Wait for it to finish before running the
next step. Each script includes all earlier changes, so you can repeat a step
or jump ahead after setup.

Step 2 also sees background activity. Step 3 filters the events returned to the
application; libsinsp still processes the underlying events it needs for state.
Step 4 prints lines such as `execve pid=1234 name=id`. PIDs and counts will vary.

| Folder | Contents |
| --- | --- |
| `presentation/` | Slides and presenter notes |
| `scripts/mac/` | Mac setup and steps 1–4 |
| `scripts/windows/` | Windows setup and steps 1–4 |
| `src/` | Created by step 1, then updated by later steps |

Stop the VM afterward with `multipass stop falco-lab` from your host terminal.

The collector monitors the Ubuntu VM's kernel, not your Mac or Windows host.
It uses libsinsp over libscap's modern eBPF engine. It does not load Falco rules.
This is a teaching example, not a production agent.

First setup downloads the latest code from Falco’s default branch into `.deps/`
inside the VM. Rerunning setup reuses that checkout and preserves source files.
Dependencies retain their upstream licenses. No node-agent code is vendored.

Windows scripts still need a native Windows rehearsal. A fresh build against the
latest upstream libraries has not been verified.

[Upstream Falco libs](https://github.com/falcosecurity/libs)
