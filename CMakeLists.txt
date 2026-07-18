cmake_minimum_required(VERSION 3.20)
project(lucid VERSION 0.1.0 LANGUAGES CXX)

# Lucid - Functional Processing Unit
# ===================================
# This CMake project manages Verilator simulations and C++ testbenches.
# RTL synthesis is handled by Yosys/Gowin toolchain (not CMake).

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find dependencies
find_package(verilator QUIET)

# Simulation targets
add_subdirectory(simulation)
add_subdirectory(verification)
