# libfe_ar_core.so: the shared C core (packages/fe_ar/src) plus its JNI glue.
# The same C sources are compiled into the iOS pod (ios/Classes/fe_ar_core_shim.c),
# so both platforms decode tiles, pick and fit corners with one implementation.
cmake_minimum_required(VERSION 3.18.1)
project(fe_ar_core C)

set(FE_AR_CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../src)

add_library(fe_ar_core SHARED
    ${FE_AR_CORE_DIR}/fe_ar_core.c
    fe_ar_jni.c)

target_include_directories(fe_ar_core PRIVATE ${FE_AR_CORE_DIR})
set_target_properties(fe_ar_core PROPERTIES C_STANDARD 99 C_STANDARD_REQUIRED ON)
target_compile_options(fe_ar_core PRIVATE -O2 -Wall -Wextra -fvisibility=hidden)
# Android 15+ devices may use 16 KB pages; Play requires 16 KB-aligned
# native libraries for new app updates.
target_link_options(fe_ar_core PRIVATE "-Wl,-z,max-page-size=16384")
target_link_libraries(fe_ar_core m)
