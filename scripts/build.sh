#!/usr/bin/env bash
set -euo pipefail

root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
bash "$root_dir/scripts/doctor.sh"
if (( EUID == 0 )); then
    echo 'Build as your regular VM user. Only capture requires sudo.' >&2
    exit 1
fi
libs_dir="$root_dir/.deps/falcosecurity-libs"
libs_ref=$(tr -d '\r\n' < "$root_dir/FALCO_LIBS_REF")
if [[ ! $libs_ref =~ ^[0-9a-f]{40}$ ]]; then
    echo 'FALCO_LIBS_REF must contain a full commit SHA.' >&2
    exit 1
fi
mkdir -p "$root_dir/.deps"
if [[ ! -d "$libs_dir/.git" ]]; then
    git init "$libs_dir"
    git -C "$libs_dir" remote add origin https://github.com/falcosecurity/libs.git
fi
if ! git -C "$libs_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$libs_dir" fetch --depth 1 origin "$libs_ref"
    git -C "$libs_dir" checkout --detach "$libs_ref"
fi
if [[ $(git -C "$libs_dir" rev-parse HEAD) != "$libs_ref" ]]; then
    echo 'Dependency revision differs from FALCO_LIBS_REF. Move .deps/ and build/ aside and rebuild.' >&2
    exit 1
fi

# Same integration point as node-agent. Keep our source in place so edits rebuild
# only the agent. Appending this once also makes reruns independent of internet.
examples="$libs_dir/userspace/libsinsp/examples/CMakeLists.txt"
entry='add_subdirectory("${WORKSHOP_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/workshop")'
if ! grep -Fqx "$entry" "$examples"; then
    printf '\n%s\n' "$entry" >> "$examples"
fi
cmake -S "$libs_dir" -B "$root_dir/build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DUSE_BUNDLED_DEPS=ON \
    -DBUILD_LIBSCAP_MODERN_BPF=ON \
    -DCREATE_TEST_TARGETS=OFF \
    -DWORKSHOP_SOURCE_DIR="$root_dir/src"
# Keep memory use predictable on laptops. Set BUILD_JOBS=2 if the VM has room.
cmake --build "$root_dir/build" --target workshop-agent --parallel "${BUILD_JOBS:-1}"
printf '\nBuilt: %s/build/bin/workshop-agent\n' "$root_dir"
