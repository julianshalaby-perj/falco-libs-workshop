// BSides Atlanta: start here, then paste the numbered snippets.
#include <chrono>
#include <cstdint>
#include <iostream>
#include <stdexcept>

#include <libscap/scap.h>
#include <libsinsp/sinsp.h>
#include <libsinsp/threadinfo.h>

int main() {
    try {
        sinsp inspector;

        // STEP 2: Paste snippets/02-filter-execs.cpp here, before opening capture.

        inspector.open_modern_bpf();
        inspector.start_capture();
        std::cout << "Attached to the Ubuntu kernel." << std::endl;

        // STEP 1 BEGIN: Replace these two lines with snippets/01-read-events.cpp.
        std::cout << "Press Enter to stop." << std::endl;
        std::cin.get();
        // STEP 1 END

        inspector.stop_capture();
        inspector.close();
        std::cout << "Capture stopped." << std::endl;
        return 0;
    } catch(const std::exception& error) {
        std::cerr << error.what() << std::endl;
        return 1;
    }
}
