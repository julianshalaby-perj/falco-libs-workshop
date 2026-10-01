// Paste at STEP 2 in src/main.cpp, before open_modern_bpf().
inspector.set_filter("evt.type in (execve, execveat) and evt.dir=<");
