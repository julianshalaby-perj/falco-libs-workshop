// Replace the two lines between STEP 1 BEGIN and STEP 1 END in src/main.cpp.
std::uint64_t received = 0;
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
        throw std::runtime_error(inspector.getlasterr());
    }
    ++received;

    // STEP 3: Paste snippets/03-process-context.cpp here.
}
std::cout << "Received " << received << " events." << std::endl;
