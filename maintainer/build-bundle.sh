#!/usr/bin/env bash
set -euo pipefail
# Maintainer-only: run on Ubuntu 24.04, once per architecture.
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source /etc/os-release
[[ $ID == ubuntu && $VERSION_ID == 24.04 ]] || { echo 'Use Ubuntu 24.04.' >&2; exit 1; }
case $(uname -m) in x86_64|aarch64) ;; *) exit 1 ;; esac
sudo apt-get update
sudo apt-get install -y --no-install-recommends build-essential ca-certificates clang cmake git pkg-config libelf-dev zlib1g-dev python3 linux-tools-generic
# Ubuntu's /usr/sbin/bpftool wrapper may not match the CI runner's Azure kernel.
bpftool_exe=$(find /usr/lib/linux-tools -type f -name bpftool | sort -V | tail -n 1)
[[ -n "$bpftool_exe" ]] || { echo 'bpftool is missing.' >&2; exit 1; }
work_dir="$root_dir/.artifacts/bundle-build"
mkdir -p "$work_dir"
libs_dir="$work_dir/libs"
if [[ ! -d "$libs_dir/.git" ]]; then
    git clone --depth 1 https://github.com/falcosecurity/libs.git "$libs_dir"
fi
# CI resolves one upstream revision for both architectures.
if [[ -n ${FALCO_COMMIT:-} ]]; then
    git -C "$libs_dir" fetch --depth 1 origin "$FALCO_COMMIT"
    git -C "$libs_dir" checkout --detach FETCH_HEAD
fi
bash "$root_dir/scripts/mac/step-3.sh"
mkdir -p "$work_dir/collector" "$work_dir/build/.cmake/api/v1/query"
cp "$root_dir/src/main.cpp" "$work_dir/collector/main.cpp"
cat > "$work_dir/collector/CMakeLists.txt" <<'CMAKE'
add_executable(workshop-agent main.cpp)
target_compile_features(workshop-agent PRIVATE cxx_std_17)
target_link_libraries(workshop-agent sinsp)
CMAKE
entry="add_subdirectory(\"$work_dir/collector\" \"\${CMAKE_BINARY_DIR}/workshop\")"
examples="$libs_dir/userspace/libsinsp/examples/CMakeLists.txt"
if ! grep -Fqx "$entry" "$examples"; then printf '\n%s\n' "$entry" >> "$examples"; fi
: > "$work_dir/build/.cmake/api/v1/query/codemodel-v2"
cmake -S "$libs_dir" -B "$work_dir/build" \
    -DCMAKE_BUILD_TYPE=Release -DUSE_BUNDLED_DEPS=ON \
    -DBUILD_LIBSCAP_MODERN_BPF=ON -DCREATE_TEST_TARGETS=OFF \
    -DBUILD_LIBSINSP_EXAMPLES=ON -DMODERN_BPFTOOL_EXE="$bpftool_exe"
cmake --build "$work_dir/build" --target workshop-agent --parallel 2
python3 "$root_dir/maintainer/package-bundle.py" "$work_dir"
# Prove the bundle works after the original source/build trees are removed from view.
mv "$work_dir/libs" "$work_dir/libs-original"
mv "$work_dir/build" "$work_dir/build-original"
mkdir -p "$work_dir/relocated"
tar -xzf "$root_dir/.artifacts/dist/falco-libs-ubuntu24.04-$(uname -m).tar.gz" -C "$work_dir/relocated"
for stage in 1 2 3; do
    bash "$root_dir/scripts/mac/step-$stage.sh"
    cat > "$root_dir/src/CMakeLists.txt" <<'CMAKE'
cmake_minimum_required(VERSION 3.16)
project(workshop-agent LANGUAGES CXX)
find_package(FalcoWorkshop CONFIG REQUIRED)
add_executable(workshop-agent main.cpp)
target_compile_features(workshop-agent PRIVATE cxx_std_17)
target_link_libraries(workshop-agent sinsp)
set_target_properties(workshop-agent PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/../bin")
CMAKE
    cmake -S "$root_dir/src" -B "$work_dir/verify-$stage" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$work_dir/relocated/falco-libs"
    cmake --build "$work_dir/verify-$stage" --parallel 2
    sudo "$work_dir/bin/workshop-agent" > "$work_dir/stage-$stage.jsonl" 2> "$work_dir/stage-$stage.log"
done
python3 - "$work_dir" <<'PY'
import json
import pathlib
import sys
root = pathlib.Path(sys.argv[1])
for stage in (1, 2, 3):
    records = [json.loads(line) for line in (root / f'stage-{stage}.jsonl').read_text().splitlines()]
    assert 'Capture stopped.' in (root / f'stage-{stage}.log').read_text()
    assert bool(records) == (stage != 1), (stage, len(records))
    assert all('event' in r and 'timestamp_ns' in r for r in records)
    if stage == 3:
        assert any('pid' in r and 'name' in r for r in records)
    print(f'Stage {stage}: {len(records)} valid events, capture stopped.')
PY
