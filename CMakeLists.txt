cmake_minimum_required(VERSION 3.14)
project(HelloWorld CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Основна програма
add_executable(hello main.cpp math_operations.cpp)

# Налаштування тестів
enable_testing()
include(FetchContent)

FetchContent_Declare(
  googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG        main
)

# Важливо для Windows: використовувати спільну бібліотеку runtime
set(gtest_force_shared_crt ON)

FetchContent_MakeAvailable(googletest)

# Створення тестового файлу
# Зверніть увагу: ми вказуємо шлях tests/unit_tests.cpp
add_executable(run_tests tests/unit_tests.cpp math_operations.cpp)

# === ОСЬ ЦЕЙ РЯДОК ВИПРАВЛЯЄ ПОМИЛКУ ===
# Він каже компілятору шукати math_operations.h у папці з CMakeLists.txt
target_include_directories(run_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(run_tests GTest::gtest_main)

include(GoogleTest)
gtest_discover_tests(run_tests)
