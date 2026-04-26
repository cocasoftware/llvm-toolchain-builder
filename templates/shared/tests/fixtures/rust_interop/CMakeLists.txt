cmake_minimum_required(VERSION 3.21)
project(rust_interop_test LANGUAGES C CXX)

# Include the COCA Rust module
include(${COCA_TOOLCHAIN_ROOT}/cmake/coca_rust.cmake)

# Build the Rust staticlib crate
coca_rust_staticlib(
    NAME mylib_rs
    CRATE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/mylib-rs
    CRATE_NAME mylib-rs
)

# Build the C++ test executable and link against the Rust staticlib
add_executable(test_rust_interop main.cpp)
target_link_libraries(test_rust_interop PRIVATE mylib_rs)
