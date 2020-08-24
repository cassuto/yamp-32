cmake_minimum_required(VERSION 3.9)
project(cpu)

set(SRCS
	"${CMAKE_CURRENT_SOURCE_DIR}/cpu.cc"
	"${CMAKE_CURRENT_SOURCE_DIR}/uart.cc"
	"${CMAKE_CURRENT_SOURCE_DIR}/termtest.cc"
	"${CMAKE_CURRENT_SOURCE_DIR}/cache.cc"
	"${CMAKE_CURRENT_SOURCE_DIR}/bpu.cc"
)

set(COMMON_WARNINGS					"-Wall")

set(CMAKE_CXX_FLAGS_DEBUG           "-g -O2 ${COMMON_WARNINGS}")
set(CMAKE_CXX_FLAGS_RELEASE         "-O2 ${COMMON_WARNINGS}")
set(CMAKE_CXX_FLAGS_PROFILE         "-O2 -pg ${COMMON_WARNINGS}")

add_executable(cpu ${SRCS})
