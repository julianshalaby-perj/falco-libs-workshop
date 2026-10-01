// Paste at STEP 3 inside the read loop, after ++received.
const auto* process = event->get_thread_info();
if(process != nullptr) {
    std::cout << event->get_name()
              << " pid=" << process->m_pid
              << " name=" << process->m_comm << std::endl;
}
