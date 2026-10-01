#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Linux ]]; then
    echo 'Run the demo in the same Linux VM as the agent.' >&2
    exit 1
fi

# A fresh private directory per run, with dummy data only. No sudo needed.
demo_dir=$(mktemp -d /tmp/falco-workshop.XXXXXX)
trap 'rm -rf -- "$demo_dir"' EXIT
printf 'Demo directory: %s\n' "$demo_dir"
printf 'hello BSides Atlanta\n' > "$demo_dir/hello.txt"
printf 'FAKE_WORKSHOP_TOKEN=not-a-real-secret\n' > "$demo_dir/secret.txt"
cat "$demo_dir/hello.txt" >/dev/null
cat "$demo_dir/secret.txt" >/dev/null
head -n 1 "$demo_dir/secret.txt" >/dev/null
cat "$demo_dir/missing.txt" >/dev/null 2>&1 || true
echo 'Generated process executions, successful file opens, and a failed open.'
