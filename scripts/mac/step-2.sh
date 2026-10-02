#!/usr/bin/env bash
set -euo pipefail
root_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

# Each step writes main.cpp and copies the shared CMake configuration, so you can repeat it or skip ahead.
mkdir -p "$root_dir/src"
cp "$root_dir/scripts/CMakeLists.txt" "$root_dir/src/CMakeLists.txt"
cat > "$root_dir/src/main.cpp" <<'COLLECTOR_CPP'
// Step 2: output raw event fields and parameters.
#include <chrono>
#include <cstdint>
#include <fstream>
#include <map>
#include <memory>
#include <string>
#include <utility>

#include <json/json.h>
#include <libscap/scap.h>
#include <libsinsp/sinsp.h>
#include <libsinsp/filter_check_list.h>
#include <libsinsp/sinsp_filtercheck.h>
#include <libsinsp/utils.h>

int main() {
    std::ofstream output("workshop-syscalls.jsonl");
    output.exceptions(std::ios::failbit | std::ios::badbit);
    sinsp inspector;
    sinsp_filter_check_list fields;
    std::map<std::string, std::unique_ptr<sinsp_filter_check>> output_fields;
    for(const auto* name : {
        "evt.type", "evt.rawtime", "evt.dir", "evt.cpu", "thread.tid",
        "evt.rawres", "evt.res", "evt.failed",
    }) {
        auto field = fields.new_filter_check_from_fldname(name, &inspector, false);
        if(!field) {
            return 1;
        }
        field->parse_field_name(name, true, false);
        output_fields.emplace(name, std::move(field));
    }
    Json::StreamWriterBuilder json;
    json["indentation"] = ""; // One JSON object per line.

    inspector.open_modern_bpf();
    // Scheduler switches are not syscalls; do not collect that tracepoint.
    inspector.mark_ppm_sc_of_interest(PPM_SC_SCHED_SWITCH, false);
    inspector.start_capture();

    /* STEP 2 ADDED: read and save events for ten seconds. */
    const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while(std::chrono::steady_clock::now() < until) {
        sinsp_evt* event = nullptr;
        const auto result = inspector.next(&event);
        if(result == SCAP_TIMEOUT || result == SCAP_FILTERED_EVENT) {
            continue;
        }
        if(result == SCAP_EOF) {
            break;
        }
        if(result != SCAP_SUCCESS) {
            return 1;
        }
        Json::Value record;
        for(const auto& [name, field] : output_fields) {
            record[name] = field->tojson(event);
        }
        // Include every captured parameter using the library's unresolved text.
        for(std::uint32_t i = 0; i < event->get_num_params(); ++i) {
            const auto* name = event->get_param_name(i);
            record[std::string("evt.rawarg.") + name] = event->get_param_value_str(name, false);
        }
        // Paths and captured data can contain invalid UTF-8.
        for(auto& value : record) {
            if(value.isString()) {
                std::string storage;
                value = std::string(utf8::sanitize(value.asString(), storage));
            }
        }
        output << Json::writeString(json, record) << '\n';
    }
    /* END STEP 2 */

    inspector.stop_capture();
    inspector.close();
    output.close();
    return 0;
}
COLLECTOR_CPP

echo 'Step 2 source ready. Run bash scripts/mac/run.sh.'
