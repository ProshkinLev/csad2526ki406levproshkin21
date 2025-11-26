cmake_minimum_required(VERSION 3.14)

project(HelloWorld LANGUAGES CXX)

# Use C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Library for math operations
add_library(math_operations STATIC math_operations.cpp)
target_include_directories(math_operations PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

# Build executable 'hello' from main.cpp
add_executable(hello main.cpp)
target_link_libraries(hello PRIVATE math_operations)

# GoogleTest setup via FetchContent
include(FetchContent)

FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG release-1.14.0
)

# Download and make available googletest
FetchContent_MakeAvailable(googletest)

enable_testing()

# Test executable
add_executable(unit_tests tests/unit_tests.cpp)
target_link_libraries(unit_tests PRIVATE gtest_main math_operations)

# Register tests with CTest / GoogleTest helper
include(GoogleTest)
gtest_discover_tests(unit_tests)
