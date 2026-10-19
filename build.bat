@echo off
rem Builds mm_sim.exe and mm_tests.exe into the bin folder.
rem Needs CMake (https://cmake.org/download/, tick "Add CMake to the PATH") and ONE of:
rem   - MinGW-w64 g++ on the PATH (easiest: https://winlibs.com ), or
rem   - Visual Studio / "Build Tools for Visual Studio" with the "Desktop development with C++" part.
setlocal
cd /d "%~dp0"
where cmake >nul 2>nul
if errorlevel 1 (
  echo CMake was not found. Install it from https://cmake.org/download/ and tick "Add CMake to the PATH".
  exit /b 1
)
if exist build\CMakeCache.txt rmdir /s /q build
where g++ >nul 2>nul
if not errorlevel 1 (
  echo Using MinGW g++
  cmake -S . -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release || exit /b 1
  cmake --build build -j || exit /b 1
  if not exist bin mkdir bin
  copy /y build\mm_sim.exe bin\ >nul
  copy /y build\mm_tests.exe bin\ >nul
) else (
  echo Using Visual Studio
  cmake -S . -B build -A x64 || exit /b 1
  cmake --build build --config Release -j || exit /b 1
  if not exist bin mkdir bin
  copy /y build\Release\mm_sim.exe bin\ >nul
  copy /y build\Release\mm_tests.exe bin\ >nul
)
echo.
echo Done. Try:  bin\mm_sim.exe replay sample_data\sample_fake_nq.mbo.zst --from 14:00
endlocal
