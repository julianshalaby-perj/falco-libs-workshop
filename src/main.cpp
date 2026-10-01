// A small libsinsp consumer for the BSides Atlanta workshop.
#include <csignal>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include <json/json.h>
#include <libscap/scap_engines.h>
#include <libsinsp/events/sinsp_events.h>
#include <libsinsp/filter_check_list.h>
#include <libsinsp/sinsp.h>
#include <libsinsp/sinsp_filtercheck.h>

volatile std::sig_atomic_t interrupted = 0;

void handle_signal(int number) {
    if(number == SIGINT || number == SIGTERM) {
        interrupted = 1;
    }
}

int main(int argc, char** argv) {
    // LAB 1: Keep process executions and file opens in the demo directory.
    std::string filter =
        "evt.dir=< and (evt.type in (execve, execveat) or "
        "(evt.type in (open, openat, openat2) and "
        "fd.name startswith /tmp/falco-workshop.))";
    for(int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if(arg == "--help") {
            std::cout << "Usage: workshop-agent [--filter 'EXPRESSION']\n"
                      << "Capture Linux syscalls with modern eBPF and print JSON lines.\n"
                      << "Run with sudo inside the workshop Ubuntu VM. Ctrl-C stops capture.\n"
                      << "Default filter: " << filter << '\n';
            return 0;
        }
        if(arg == "--filter" && i + 1 < argc) {
            filter = argv[++i];
        } else {
            std::cerr << "Unknown option or missing value: " << arg << '\n';
            return 1;
        }
    }

    try {
        std::signal(SIGINT, handle_signal);
        std::signal(SIGTERM, handle_signal);
        sinsp inspector;

        // LAB 2: Capture selection happens in the driver. Repair preserves the
        // process/FD state events that libsinsp needs, even if we don't print them.
        namespace events = libsinsp::events;
        const auto syscalls = events::sinsp_repair_state_sc_set(
            events::sc_names_to_sc_set({"execve", "execveat", "open", "openat", "openat2"}));
        inspector.set_filter(filter);

        // LAB 3: Compile field extractors once, then reuse them for every event.
        // Built-in fields suffice here. Container metadata needs more plumbing.
        const std::vector<std::string> fields = {
            "evt.time.iso8601", "evt.type", "evt.dir", "evt.rawres",
            "proc.pid", "proc.ppid", "proc.name", "proc.cmdline",
            "user.uid", "fd.name", "evt.args",
        };
        sinsp_filter_check_list field_checks;
        field_checks.add_filter_check(inspector.new_generic_filtercheck());
        std::vector<std::unique_ptr<sinsp_filter_check>> extractors;
        for(const auto& field : fields) {
            auto check = field_checks.new_filter_check_from_fldname(field, &inspector, false);
            if(!check) {
                throw std::runtime_error("Unknown field: " + field);
            }
            check->parse_field_name(field.c_str(), true, false);
            extractors.push_back(std::move(check));
        }
        Json::StreamWriterBuilder writer;
        writer["indentation"] = "";

        inspector.open_modern_bpf(DEFAULT_DRIVER_BUFFER_BYTES_DIM,
                                  DEFAULT_CPU_FOR_EACH_BUFFER, true, syscalls, false);
        inspector.start_capture();
        std::cerr << "[agent] Ready. Run bash scripts/demo.sh in another VM terminal.\n"
                  << "[agent] Filter: " << filter << '\n';
        uint64_t emitted = 0;
        while(!interrupted) {
            sinsp_evt* event = nullptr;
            const int32_t result = inspector.next(&event);
            if(result == SCAP_TIMEOUT || result == SCAP_FILTERED_EVENT) {
                continue;
            }
            if(result == SCAP_EOF) {
                break;
            }
            if(result != SCAP_SUCCESS) {
                throw std::runtime_error(inspector.getlasterr());
            }

            // libsinsp owns event. Extract now, before the next next() call.
            Json::Value row(Json::objectValue);
            for(std::size_t i = 0; i < fields.size(); ++i) {
                row[fields[i]] = extractors[i]->tojson(event);
            }

            // LAB 4: Add your detection here. See Exercise 4 in the presentation.

            std::cout << Json::writeString(writer, row) << std::endl;
            if(!std::cout) {
                throw std::runtime_error("Cannot write event to stdout");
            }
            ++emitted;
        }
        inspector.stop_capture();
        scap_stats stats{};
        inspector.get_capture_stats(&stats);
        std::cerr << "[agent] Emitted=" << emitted << " captured=" << stats.n_evts
                  << " dropped=" << stats.n_drops << '\n';
        return 0;
    } catch(const std::exception& error) {
        std::cerr << "[agent] " << error.what() << '\n'
                  << "Check sudo, kernel/BTF support, and filter/field spelling.\n";
        return 1;
    }
}
