cmake_minimum_required(VERSION 3.16)
project(mm_sim LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release)
endif()

# zstd decoder (single file, BSD licence) - so .dbn.zst files open without installing anything
add_library(zstd_dec STATIC third_party/zstd/zstddeclib.c)
target_include_directories(zstd_dec PUBLIC third_party/zstd)
target_compile_definitions(zstd_dec PRIVATE ZSTD_DISABLE_ASM=1)

find_package(Threads REQUIRED)

add_library(mm_core INTERFACE)
target_include_directories(mm_core INTERFACE src)
target_link_libraries(mm_core INTERFACE zstd_dec Threads::Threads)
if(MSVC)
  target_compile_options(mm_core INTERFACE /O2 /utf-8 /fp:precise /wd4244 /wd4267)
  target_compile_definitions(mm_core INTERFACE _CRT_SECURE_NO_WARNINGS NOMINMAX)
else()
  target_compile_options(mm_core INTERFACE -O3 -ffp-contract=off -Wall -Wextra)
endif()
if(MINGW)
  # one self-contained .exe: no libstdc++ / libgcc / winpthread DLLs needed next to it
  target_link_options(mm_core INTERFACE -static)
endif()

add_executable(mm_sim src/main.cpp src/dashboard.cpp)
target_link_libraries(mm_sim PRIVATE mm_core)

add_executable(mm_tests tests/test_main.cpp)
target_link_libraries(mm_tests PRIVATE mm_core)
