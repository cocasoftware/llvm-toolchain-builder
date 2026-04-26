cmake_minimum_required(VERSION 3.21)
project(coca_cmake_test LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(hello_cmake hello.c)
