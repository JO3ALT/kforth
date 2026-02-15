cmake_minimum_required(VERSION 3.16)
project(kforth C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

add_executable(kforth
  kforth.c
  kf_io.c
  kf_dev.c
)

target_compile_options(kforth PRIVATE -Wall -Wextra -O2)
