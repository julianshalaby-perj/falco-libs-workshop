cmake_minimum_required(VERSION 3.24)
project(workshop-agent LANGUAGES CXX)
include(FetchContent)

# Prebuilt libraries hosted in this course's repository; no Falco source build.
# For a production custom agent, build and link upstream libs for your target:
# https://github.com/falcosecurity/libs#build
set(release_url "https://github.com/julianshalaby-perj/falco-libs-workshop/releases/download/sdk-2026-10-02-v1")
if(CMAKE_SYSTEM_PROCESSOR STREQUAL "x86_64")
    set(bundle_sha256 "cd60e103b90d7745e6cb13421aa57cd67be3e05052bdf53e8ab7fbabfb6ae5e8")
elseif(CMAKE_SYSTEM_PROCESSOR STREQUAL "aarch64")
    set(bundle_sha256 "6f8e51ca0073e726e7df2d9142fd40501f26a19b6c73826fcdbb76b1d4aaf8e5")
else()
    message(FATAL_ERROR "The workshop supports x86_64 and aarch64 Ubuntu VMs.")
endif()

FetchContent_Declare(falco_libs
    URL "${release_url}/falco-libs-ubuntu24.04-${CMAKE_SYSTEM_PROCESSOR}.tar.gz"
    URL_HASH "SHA256=${bundle_sha256}"
)
FetchContent_MakeAvailable(falco_libs)
include("${falco_libs_SOURCE_DIR}/FalcoWorkshopConfig.cmake")

add_executable(workshop-agent main.cpp)
target_compile_features(workshop-agent PRIVATE cxx_std_17)
target_link_libraries(workshop-agent sinsp)
