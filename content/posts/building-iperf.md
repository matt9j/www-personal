---
title: "Building iperf3 For Android 11+"
date: 2021-09-17
draft: true
description: "Integration builds character"
tags: [
    "android",
    "seattle-community-network",
    "networks",
    "ICTD",
]
categories: [
    "software-development",
    ]
type: "post"
---

## Preamble

I've been helping out the [Seattle Community
Network](https://seattlecommunitynetwork.org) (SCN), with an ongoing project to
build a crowdsourced network performance measurement application for Android.
While understanding modern network performance, particularly wireless networks,
is *extremely* subtle, "speedtests" offer a crude yet popular way to measure a
network's performance, and are easy for general audiences to interpret.

Unsurprisingly, SCN sought to include a "speedtest" capability in their app! A
team of volunteer undergraduate researchers ([Zhennan(John)
Zhou](https://johnnzhou.github.io/) & [Ashwin
Chintalapati](https://www.linkedin.com/in/ashwin-chintalapati-a54936222/))
organized by [Esther Jang](https://infrared-ether.medium.com/) got started on
the project, and started integrating [iperf3](https://github.com/esnet/iperf)
(C, [BSD-3](https://github.com/esnet/iperf/blob/master/LICENSE) into the
application. Due to its maturity, consistent history of open source activity,
and explicit offer of "a library version of the functionality that can be used
in other programs," I thought it was a reasonable choice. After a couple of
weeks their efforts stalled though, and I was asked for some input.

This marked the beginning of the journey...

## Building in Android Studio

Since libiperf is a c library, we sought to use the Android [Native Development
Kit (NDK)](https://developer.android.com/ndk) to re-use the existing code and
integrate it directly with our android application. Under the hood the NDK
relies on the Java Native Interface (JNI) to define the interface between the
application code running in the JVM and c/c++ functions.
[John](https://johnnzhou.github.io/) wrote a set of wrappers to expose the
relevant functions to the main application via the JNI, and an ndk-build script
to build the wrappers and link in a pre-built libiperf. This approach worked,
but had the unfortunate downside of making it very diffcult to work with
libiperf from within Android studio, and reduced our visibility into the
behavior of libiperf when we were trying to debug its interaction with the main
application. The version of libiperf that worked with the external build was
very old (3.1.3 vs. the latest 3.10.1 release), we had to re-build libiperf
manually each time we made changes, and didn't have an easy way to use android
logging from within the libiperf code.

Given these shortcomings, I took up the challenge of getting the latest libiperf
to work natively with Android Studio's NDK tooling to build libiperf from source
as a part of the overall application build. While at the time of this post both
ndk-build and CMake are supported by Android Studio, most of the official
tutorials and help documentation are targeted towards the CMake approach, and
the [NDK guide](https://developer.android.com/ndk/guides) encourages projects to
choose CMake over ndk-build.

> Android Studio's default build tool to compile native libraries is CMake.
> Android Studio also supports ndk-build due to the large number of existing
> projects that use the build toolkit. However, if you are creating a new native
> library, you should use CMake.

Since I was going to make major changes to the build anyway, CMake seemed like
the way to go. Iperf 3 uses autotools for its build, and after much trial and
error, CMake documentation consulation, Google searching, soul searching, and
only a few tears, I was able to adapt SciVision's [autotools as CMake
ExternalProject
example](https://www.scivision.dev/cmake-external-project-autotools/) to build
iperf3 from CMake via its own build tooling. By using CMake's ExternalProject
capabilities, we can avoid re-creating the whole existing autotools build in
CMake, and make it easy to upgrade the underlying iperf version to keep up with
upstream releases.

Importantly though, we're not just building iperf3 via CMake, we're building
iperf3 via CMake *for Android*, and this means cross compilation is needed. I
found a [helpful blog
post](https://medium.com/@ansorod/how-to-compile-iperf3-for-android-4d67c9a7f061)
from 2020 by [Anderson Rodrigues](https://medium.com/@ansorod). In his post,
Rodrigues walks us readers through creating a standalone Android toolchain
(fortunately no longer needed since NDKr19), and then running the autotools
`./configure` step with the correct environment variables for the
cross-compilation toolchain. While this gets us to a correctly compiled library,
it still doesn't get us to full integration with Android studio.

Building from Rodrigues' approach and consulting the [latest environment
variables for autoconf from the Android developer
docs](https://developer.android.com/ndk/guides/other_build_systems), I created
the following CMakeLists.txt to translate from the build metadata passed to
CMake 3.18.1 (installed via SDK Tools Manager) from Gradle 7.0.2 in Android
Studio to the correct configuration environment variables for autotools.

```CMake
# Sets the minimum version of CMake required to build the native library.
cmake_minimum_required(VERSION 3.16.3)

set(IPERF_DIRECTORY_NAME
    iperf-3.10.1
    )

# Generate toolchain paths manually according to https://developer.android.com/ndk/guides/other_build_systems.
# This may need to be updated if the NDK changes
string(TOLOWER "${CMAKE_HOST_SYSTEM_NAME}-${CMAKE_HOST_SYSTEM_PROCESSOR}" AUTOTOOLS_EXT_BUILD_ARCH)
message(STATUS "Toolchain build architecture: ${AUTOTOOLS_EXT_BUILD_ARCH}")
SET(AUTOTOOLS_EXT_TOOLCHAIN "${CMAKE_ANDROID_NDK}/toolchains/llvm/prebuilt/${AUTOTOOLS_EXT_BUILD_ARCH}")
if(${CMAKE_ANDROID_ARCH} MATCHES "^arm$")
    SET(AUTOTOOLS_EXT_TARGET "armv7a-linux-androideabi")
elseif(${CMAKE_ANDROID_ARCH} MATCHES "^arm64$")
    SET(AUTOTOOLS_EXT_TARGET "aarch64-linux-android")
elseif(${CMAKE_ANDROID_ARCH} MATCHES "^x86$")
    SET(AUTOTOOLS_EXT_TARGET "i686-linux-android")
elseif(${CMAKE_ANDROID_ARCH} MATCHES "^x86_64$")
    SET(AUTOTOOLS_EXT_TARGET "x86_64-linux-android")
else()
    message(FATAL_ERROR "No target string defined for arch: ${CMAKE_ANDROID_ARCH}")
endif()

SET(AUTOTOOLS_EXT_ABI "24")

if(NOT ${CMAKE_C_COMPILER_TARGET} MATCHES "android.*${AUTOTOOLS_EXT_ABI}$")
    message(ERROR "The CMake ABI version does not match the version set by gradle")
    message(ERROR "Update the AUTOTOOLS_EXT_ABI version to match")
    message(FATAL_ERROR "ABI ${AUTOTOOLS_EXT_ABI} does not match target ${CMAKE_C_COMPILER_TARGET}")
endif()

# Link libiperf statically but with position independent code support to be embedded in a higher level dynamic library
SET(AUTOMAKE_EXT_CXX_FLAGS "${CMAKE_CXX_FLAGS} -static -fPIC")
SET(AUTOMAKE_EXT_C_FLAGS "${CMAKE_C_FLAGS} -static -fPIC")

include(ExternalProject)
ExternalProject_Add(
        iperf_autotools
        SOURCE_DIR ${IPERF_DIRECTORY_NAME}
        CONFIGURE_COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/${IPERF_DIRECTORY_NAME}/configure --host ${AUTOTOOLS_EXT_TARGET} AR=${AUTOTOOLS_EXT_TOOLCHAIN}/bin/llvm-ar CC=${AUTOTOOLS_EXT_TOOLCHAIN}/bin/${AUTOTOOLS_EXT_TARGET}${AUTOTOOLS_EXT_ABI}-clang AS=${AUTOTOOLS_EXT_TOOLCHAIN}/bin/${AUTOTOOLS_EXT_TARGET}${AUTOTOOLS_EXT_ABI}-clang CXX=${AUTOTOOLS_EXT_TOOLCHAIN}/bin/${AUTOTOOLS_EXT_TARGET}${AUTOTOOLS_EXT_ABI}-clang++ LD=${AUTOTOOLS_EXT_TOOLCHAIN}/bin/ld RANLIB=${AUTOTOOLS_EXT_TOOLCHAIN}/bin/llvm-ranlib STRIP=${AUTOTOOLS_EXT_TOOLCHAIN}/bin/llvm-strip CFLAGS=${AUTOMAKE_EXT_C_FLAGS} CXXFLAGS=${AUTOMAKE_EXT_CXX_FLAGS} --without-openssl --prefix=${CMAKE_CURRENT_BINARY_DIR}/${IPERF_DIRECTORY_NAME}
        PREFIX ${IPERF_DIRECTORY_NAME}
        BUILD_COMMAND make
        BUILD_IN_SOURCE 1
        BUILD_BYPRODUCTS ${CMAKE_CURRENT_BINARY_DIR}/${IPERF_DIRECTORY_NAME}/lib/libiperf.a
)

# Create a CMake "imported" "interface" library representing the outputs from the autotools process.
add_library(iperf INTERFACE IMPORTED GLOBAL)

# Let CMake know these directories can be created since they are referred below-- they would have
# been eventually created by automake
file (MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${IPERF_DIRECTORY_NAME}/lib")
file (MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/${IPERF_DIRECTORY_NAME}/include")

# Pass the headers and libraries created by automake to dependent targets for linking and/or inclusion.
target_include_directories(iperf INTERFACE ${CMAKE_CURRENT_BINARY_DIR}/${IPERF_DIRECTORY_NAME}/include)
target_link_libraries(iperf INTERFACE "${CMAKE_CURRENT_BINARY_DIR}/${IPERF_DIRECTORY_NAME}/lib/libiperf.a")

# Make sure the iperf interface library target triggers the autotools build.
add_dependencies(iperf iperf_autotools)

# Add extra includes based on the current structure of the wrapper codebase.
# This somewhat breaks the API encapsulation.
# TODO(matt9j) Should ultimately not be needed if the API interface were used cleanly
target_include_directories(iperf INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/${IPERF_DIRECTORY_NAME}/src)
target_include_directories(iperf INTERFACE ${CMAKE_CURRENT_BINARY_DIR}/${IPERF_DIRECTORY_NAME}/src)

```

This current implementation has the downside of specifying the Android ABI
manually, but I'm hoping it will become obsolete as the Android NDK support
built into CMake improves with CMake 3.21. For now though this has allowed us to
build the library on demand for all platforms supported by Android Studio,
including both debug and release versions with symbols to allow integrated
debugging in Android Studio! Hopefully it can be useful to you as well, and can
save you the few days I spent learning to untangle the Android native build
process!

## Hindsight

Looking back on this work and the integration struggles we overcame (to be
detailed in a future post), I'm quite intrigued by the easy crossplatform builds
promised by Golang, and am curious if [ethr](https://github.com/microsoft/ethr)
(Golang, MIT) might have been the better choice. If anyone has experience
integrating ethr into a high-level application I would love to hear how it went!
