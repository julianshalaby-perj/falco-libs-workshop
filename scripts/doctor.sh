#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Linux ]]; then
    echo 'Live capture needs Linux. Enter the Ubuntu VM first: multipass shell falco-lab' >&2
    exit 1
fi
printf 'Kernel: %s\nArchitecture: %s\n' "$(uname -r)" "$(uname -m)"
case $(uname -m) in
    x86_64|aarch64) ;;
    *) echo 'This workshop targets x86_64 or aarch64 Linux.' >&2; exit 1 ;;
esac
kernel_version=$(uname -r)
IFS=. read -r kernel_major kernel_minor _ <<< "$kernel_version"
if (( kernel_major < 5 || (kernel_major == 5 && kernel_minor < 8) )); then
    echo 'Modern eBPF needs kernel 5.8 or newer for this lab. Use Ubuntu 24.04.' >&2
    exit 1
fi
if [[ ! -r /sys/kernel/btf/vmlinux ]]; then
    echo 'Missing readable /sys/kernel/btf/vmlinux. Use the stock Ubuntu VM kernel.' >&2
    exit 1
fi
for tool in cmake make git g++ clang bpftool pkg-config jq nano; do
    if ! command -v "$tool" >/dev/null; then
        printf 'Missing %s. Run bash scripts/setup.sh.\n' "$tool" >&2
        exit 1
    fi
done
bpftool version
cmake --version | head -n 1
echo 'Basic prerequisites passed. Starting the agent with sudo verifies actual BPF loading.'
