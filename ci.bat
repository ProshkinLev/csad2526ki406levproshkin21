
@echo off
setlocal

echo --- Starting CI Build and Test ---
echo.

REM Create build directory if it doesn't exist
if not exist build mkdir build
if errorlevel 1 goto fail

REM Change into build directory
cd build
if errorlevel 1 goto fail

REM Configure the project using CMake and the Ninja generator
echo [STEP] Configuring project...
cmake .. -G "Ninja"
if errorlevel 1 goto fail

REM Build the project
echo.
echo [STEP] Building project...
cmake --build .
if errorlevel 1 goto fail

REM Run the tests with CTest
echo.
echo [STEP] Running tests...
ctest --output-on-failure
if errorlevel 1 goto fail

echo.
echo --- CI SUCCEEDED ---
goto end

:fail
echo.
echo !!! CI FAILED !!!
exit /b 1

:end
exit /b 0
