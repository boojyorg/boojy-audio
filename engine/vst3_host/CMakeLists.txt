cmake_minimum_required(VERSION 3.14)

# Enable Objective-C++ for macOS
if(APPLE)
    project(vst3_host LANGUAGES C CXX OBJCXX)
else()
    project(vst3_host LANGUAGES C CXX)
endif()

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# VST3 SDK requires one of these to be defined
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_definitions(-D_DEBUG)
else()
    add_definitions(-DNDEBUG -DRELEASE)
endif()

# Find VST3 SDK (relative path from this CMakeLists.txt)
set(VST3_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../vst3sdk")

if(NOT EXISTS "${VST3_SDK_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "VST3 SDK not found at ${VST3_SDK_DIR}")
endif()

# Add VST3 SDK subdirectory
# Note: We need to build a minimal set of VST3 SDK components
set(SMTG_CREATE_VST2_VERSION OFF CACHE BOOL "" FORCE)
set(SMTG_ADD_VST3_PLUGINS_SAMPLES OFF CACHE BOOL "" FORCE)
set(SMTG_ADD_VST3_HOSTING_SAMPLES OFF CACHE BOOL "" FORCE)

# Enable ARC for Objective-C++ files (required by module_mac.mm)
if(APPLE)
    set(CMAKE_OBJCXX_FLAGS "${CMAKE_OBJCXX_FLAGS} -fobjc-arc")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fobjc-arc")
endif()

# Include VST3 SDK
add_subdirectory(${VST3_SDK_DIR} vst3sdk_build EXCLUDE_FROM_ALL)

# Our VST3 host library
set(VST3_HOST_SOURCES
    vst3_host.cpp
    vst3_host.h
    # EventList from SDK for MIDI event queueing (not included in sdk_hosting)
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/eventlist.cpp
    ${VST3_SDK_DIR}/public.sdk/source/vst/hosting/eventlist.h
)

# Add macOS-specific Objective-C++ file
if(APPLE)
    list(APPEND VST3_HOST_SOURCES vst3_host_mac.mm)
endif()

add_library(vst3_host STATIC ${VST3_HOST_SOURCES})

# Include directories
target_include_directories(vst3_host PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${VST3_SDK_DIR}
)

# Link against VST3 SDK components
target_link_libraries(vst3_host
    sdk_hosting
    sdk
    base
)

# Platform-specific settings
if(APPLE)
    find_library(COREFOUNDATION_FRAMEWORK CoreFoundation)
    find_library(FOUNDATION_FRAMEWORK Foundation)
    find_library(COCOA_FRAMEWORK Cocoa)

    target_link_libraries(vst3_host
        ${COREFOUNDATION_FRAMEWORK}
        ${FOUNDATION_FRAMEWORK}
        ${COCOA_FRAMEWORK}
    )

    # Set macOS deployment target
    set_target_properties(vst3_host PROPERTIES
        MACOSX_DEPLOYMENT_TARGET "10.13"
    )
elseif(WIN32)
    # Windows-specific settings
    target_compile_definitions(vst3_host PRIVATE
        _WIN32
        NOMINMAX
        WIN32_LEAN_AND_MEAN
    )

    # Link Windows COM libraries needed for VST3
    target_link_libraries(vst3_host
        ole32
        uuid
    )
elseif(UNIX)
    # Linux-specific settings
    target_link_libraries(vst3_host
        pthread
        dl
    )
endif()

# Compiler flags
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(vst3_host PRIVATE
        -Wall
        -Wextra
        -Wno-unused-parameter
    )
endif()

# Output library to predictable location
set_target_properties(vst3_host PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

# Install targets
install(TARGETS vst3_host
    ARCHIVE DESTINATION lib
)

install(FILES vst3_host.h
    DESTINATION include
)
