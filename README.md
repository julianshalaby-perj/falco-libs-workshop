# Falco libs workshop · BSides Atlanta

Build a small C++ agent that captures real Linux syscalls using Falco's
libscap and libsinsp. Mac and Windows attendees run it inside an Ubuntu VM.

**[Download the workshop slides](https://github.com/julianshalaby-perj/falco-libs-workshop/raw/refs/heads/main/presentation/falco-libs-intro.pptx)**

The slides are the complete attendee guide: fresh-computer setup, four exercises,
solutions, troubleshooting, and cleanup. Setup is on slide 2.
The live session starts at slide 3 and takes roughly 45–60 minutes.

Clone this repo, then run `bash scripts/setup-mac.sh` on macOS or
`powershell -ExecutionPolicy Bypass -File scripts/setup-windows.ps1` on Windows.
If Multipass is missing, setup asks before downloading and running Canonical’s
installer. Approve the OS administrator prompt and, on Windows, complete the
installer. If it requests a restart, reboot and rerun setup. Setup then creates
the Ubuntu VM, copies the source, installs dependencies, and builds the agent. Re-running setup keeps
your existing VM source edits. No GitHub account is needed.

After editing the agent, rebuild inside the VM from `~/falco-libs-workshop`:

```sh
cmake --build build --target workshop-agent -j 1
```

| Folder | Contents |
| --- | --- |
| `presentation/` | The slides, including presenter notes |
| `src/` | One C++ agent and its CMake configuration |
| `scripts/` | Standalone Mac/Windows setup and a dummy activity demo |

This is a local learning project. It uses Falco libraries directly and does not
load Falco YAML rules. The VM is the monitored machine. Activity on your Mac or
Windows host is outside its capture boundary.

## Validation status

Target: Ubuntu 24.04, x86_64 or arm64, with the stock kernel and BTF support.
The source was checked against the pinned Falco headers and Bash syntax was
checked. **VM setup, the full Linux build, and live capture have not yet been run.**
Rehearse the setup and all four exercises on attendee platforms before the event.

`FALCO_LIBS_REF` pins the library revision. The build downloads dependencies into
`.deps/`; dependencies retain their upstream licenses. This project does not
vendor node-agent code.

[Upstream Falco libs](https://github.com/falcosecurity/libs/tree/e72873882967cdd86b8753eca09ea3e9f91ccd4a)
