#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:$PATH"
if ! command -v multipass >/dev/null; then
    echo 'Multipass is not installed. Nothing to tear down.'
    exit 0
fi
# Check the daemon first so a connection failure is not mistaken for no VM.
instances=$(multipass list --format csv)
if ! printf '%s\n' "$instances" | awk -F, '$1 == "falco-lab" { found=1 } END { exit !found }'; then
    echo 'No falco-lab VM exists. Nothing to tear down.'
    exit 0
fi

echo 'This permanently deletes the falco-lab VM and everything inside it.'
echo 'Your local source and logs, other VMs, and Multipass installation stay.'
answer=''
read -r -p 'Delete falco-lab? [y/N] ' answer || true
case "$answer" in
    y|Y|yes|YES) ;;
    *) echo 'Cancelled. The VM is unchanged.'; exit 0 ;;
esac
# Purge only this named VM. Never use the global multipass purge command.
multipass delete --purge falco-lab
echo 'Workshop VM and disk removed. Run setup again to recreate them.'
