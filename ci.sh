#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- Starting CI Build and Test ---"
echo

# 1. Create the build directory if it doesn't exist.
# The -p flag prevents an error if the directory already exists.
mkdir -p build

# 2. Change into the build directory.
cd build

# 3. Configure the project using CMake and the Ninja generator.
echo "[STEP] Configuring project..."
cmake .. -G "Ninja"

# 4. Build the project.
echo
echo "[STEP] Building project..."
cmake --build .

# 5. Run the tests with CTest.
echo
echo "[STEP] Running tests..."
ctest --output-on-failure

# 6. If all previous commands succeeded, print the success message.
echo
echo "--- CI SUCCEEDED ---"
