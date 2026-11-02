cmake_minimum_required(VERSION 3.5.0)
project(nekomusic_pow)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(pow SHARED sha256.cpp)
target_link_libraries(pow PUBLIC libace_napi.z.so)
