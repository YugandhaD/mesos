# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# GENERAL OPTIONS.
##################
option(VERBOSE "Enable verbose CMake statements and compilation output" ON)
set(CMAKE_VERBOSE_MAKEFILE ${VERBOSE})

if (NOT WIN32)
  set(DEFAULT_BUILD_SHARED_LIBS ON)
else ()
  set(DEFAULT_BUILD_SHARED_LIBS OFF)
endif ()

option(BUILD_SHARED_LIBS "Build shared libraries." ${DEFAULT_BUILD_SHARED_LIBS})

option(ENABLE_PRECOMPILED_HEADERS
  "Enable auto-generated precompiled headers using cotire" ${WIN32})

if (NOT WIN32 AND ENABLE_PRECOMPILED_HEADERS)
  message(
    FATAL_ERROR
    "Precompiled headers are only supported on Windows.  See MESOS-7322.")
endif ()

if (ENABLE_PRECOMPILED_HEADERS)
  # By default Cotire generates both precompiled headers and a "unity" build.
  # A unity build is where all the source files in a target are combined into
  # a single source file to reduce the number of files that need to be opened
  # and read. We disable "unity" builds for now.
  set(COTIRE_ADD_UNITY_BUILD FALSE)
  set(COTIRE_VERBOSE ${VERBOSE})
endif ()

if (WIN32)
  # In MSVC 1900, there are two bugs in the linker, one that causes linking
  # libmesos to occasionally take hours, and one that causes us to be able to
  # fail to open the `mesos-x.lib` file. These have been confirmed as bugs with
  # the MSVC backend team by hausdorff.
  set(PREFERRED_TOOLSET "host=x64")
  if (NOT CMAKE_GENERATOR_TOOLSET MATCHES ${PREFERRED_TOOLSET})
    message(
      FATAL_ERROR
      "The x64 toolset MUST be used. See MESOS-6720 for details. "
      "Please use `cmake -T ${PREFERRED_TOOLSET}`."
  )
  endif ()
endif ()


# 3RDPARTY OPTIONS.
###################
option(
  REBUNDLED
  "Use dependencies from the 3rdparty folder (instead of internet)"
  TRUE)

option(
  ENABLE_LIBEVENT
  "Use libevent instead of libev as the core event loop implementation"
  FALSE)

option(
  ENABLE_SSL
  "Build libprocess with SSL support"
  FALSE)

option(
  HAS_AUTHENTICATION
  "Build Mesos against authentication libraries"
  TRUE)

if (WIN32 AND HAS_AUTHENTICATION)
  message(
    FATAL_ERROR
    "Windows builds of Mesos currently do not support agent to master "
    "authentication. To build without this capability, pass "
    "`-DHAS_AUTHENTICATION=0` as an argument when you run CMake.")
endif ()

# If 'REBUNDLED' is set to FALSE, this will cause Mesos to build against the
# specified dependency repository. This is especially useful for Windows
# builds, because building on MSVC 1900 requires newer versions of some
# dependencies than the ones bundled in the Mesos repository.
set(
  3RDPARTY_DEPENDENCIES "https://github.com/3rdparty/mesos-3rdparty/raw/master"
  CACHE STRING
    "URL or filesystem path with a fork of the canonical 3rdparty repository")

if (WIN32 AND REBUNDLED)
  message(
    WARNING
    "On Windows, the required versions of:\n"
    "  * ZooKeeper\n"
    "  * protobuf\n"
    "  * glog\n"
    "  * libevent\n"
    "  * curl\n"
    "  * libapr\n"
    "  * zlib\n"
    "do not come rebundled in the Mesos repository.  They will be downloaded from "
    "the Internet, even though the `REBUNDLED` flag was set.")
endif ()

if (WIN32 AND (NOT ENABLE_LIBEVENT))
  message(
    FATAL_ERROR
    "Windows builds of Mesos currently do not support libev, the default event "
    "loop used by Mesos.  To opt into using libevent, pass "
    "`-DENABLE_LIBEVENT=1` as an argument when you run CMake.")
endif ()

if (ENABLE_SSL AND (NOT ENABLE_LIBEVENT))
  message(
    FATAL_ERROR
    "'ENABLE_SSL' currently requires 'ENABLE_LIBEVENT'.")
endif ()


# SYSTEM CHECKS.
################
# Check that we are targeting a 64-bit architecture.
if (NOT (CMAKE_SIZEOF_VOID_P EQUAL 8))
  message(
    FATAL_ERROR
    "Mesos requires that we compile to a 64-bit target. Following are some "
    "examples of how to accomplish this on some well-used platforms:\n"
    "  * Linux: (on gcc) set `CMAKE_CXX_FLAGS` to include `-m64`:\n"
    "    `cmake -DCMAKE_CXX_FLAGS=-m64 `.\n"
    "  * Windows: use the VS win64 CMake generator:\n"
    "    `cmake -G \"Visual Studio 15 2017 Win64\"`.\n"
    "  * OS X: add `x86_64` to the `CMAKE_OSX_ARCHITECTURES`:\n"
    "    `cmake -DCMAKE_OSX_ARCHITECTURES=x86_64`.\n")
endif ()

# Make sure C++ 11 features we need are supported.
# This is split into two cases: Windows and "other platforms".
#   * For "other platforms", we simply check if the C++11 flags work
#   * For Windows, C++11 is enabled by default on MSVC 1900.
#     We just check the MSVC version.
CHECK_CXX_COMPILER_FLAG("-std=c++11" COMPILER_SUPPORTS_CXX11)
if (WIN32)
  # Versions of Visual Studio older than 2017 do not support all core features
  # of C++14, which prevents Mesos from moving past C++11. This adds a
  # non-fatal deprecation warning.
  set(PREFERRED_GENERATOR "Visual Studio 15 2017")
  if (NOT CMAKE_GENERATOR MATCHES ${PREFERRED_GENERATOR})
    message(
      WARNING
      "Mesos is deprecating support for ${CMAKE_GENERATOR}. "
      "Please use ${PREFERRED_GENERATOR}."
  )
  endif ()

  # We don't support compilation against mingw headers (which, e.g., Clang on
  # Windows does at this point), because this is likely to cost us more effort
  # to support than it will be worth at least in the short term.
  if (NOT CMAKE_CXX_COMPILER_ID MATCHES MSVC)
    message(
      FATAL_ERROR
      "Mesos does not support compiling on Windows with "
      "${CMAKE_CXX_COMPILER_ID}. Please use MSVC.")
  endif ()

  # MSVC 1900 supports C++11; earlier versions don't. So, warn if you try to
  # use anything else.
  if (${MSVC_VERSION} LESS 1900)
    message(
      FATAL_ERROR
      "Mesos does not support compiling on MSVC versions earlier than 1900. "
      "Please use MSVC 1900 (included with Visual Studio 2015 or later).")
  endif ()
endif ()


# POSIX CONFIGURATION.
######################
if (NOT WIN32)
  if (NOT COMPILER_SUPPORTS_CXX11)
    message(
      FATAL_ERROR
      "The compiler ${CMAKE_CXX_COMPILER} does not support the `-std=c++11` "
      "flag. Please use a different C++ compiler.")
  endif ()

  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++11")

  # Directory structure for some build artifacts.
  # This is defined for use in tests.
  set(EXEC_INSTALL_PREFIX  ${CMAKE_INSTALL_PREFIX})
  set(SHARE_INSTALL_PREFIX ${CMAKE_INSTALL_PREFIX}/share)
  set(DATA_INSTALL_PREFIX  ${SHARE_INSTALL_PREFIX}/mesos)

  set(LIBEXEC_INSTALL_DIR     ${EXEC_INSTALL_PREFIX}/libexec)
  set(PKG_LIBEXEC_INSTALL_DIR ${LIBEXEC_INSTALL_DIR}/mesos)
  set(LIB_INSTALL_DIR         ${EXEC_INSTALL_PREFIX}/libmesos)
endif ()


# LINUX CONFIGURATION.
######################
string(COMPARE EQUAL ${CMAKE_SYSTEM_NAME} "Linux" LINUX)


# WINDOWS CONFIGURATION.
########################
if (WIN32)
  # Speed up incremental linking for the VS compiler/linker, for more info, see:
  # https://blogs.msdn.microsoft.com/vcblog/2014/11/12/speeding-up-the-incremental-developer-build-scenario/
  foreach (type EXE SHARED STATIC MODULE)
    string(APPEND CMAKE_${type}_LINKER_FLAGS_DEBUG " /debug:fastlink")
  endforeach ()

  # COFF/PE and friends are somewhat limited in the number of sections they
  # allow for an object file. We use this to avoid those problems.
  string(APPEND CMAKE_CXX_FLAGS " /bigobj -DGOOGLE_GLOG_DLL_DECL= /vd2")

  # Build against the multi-threaded version of the C runtime library (CRT).
  if (BUILD_SHARED_LIBS)
    message(WARNING "Building with shared libraries is a work-in-progress.")

    set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)

    # Use dynamic CRT.
    set(CRT " /MD")
  else ()
    # Use static CRT.
    set(CRT " /MT")

    # TODO(andschwa): Define this closer to its usage; anything that includes
    # `curl.h` has to set this so that the declspec is correct.
    string(APPEND CMAKE_CXX_FLAGS " -DCURL_STATICLIB")
  endif ()

  # NOTE: We APPEND ${CRT} rather than REPLACE so it gets picked up by
  # dependencies.
  foreach (lang C CXX)
    # Enable multi-threaded compilation.
    # NOTE: We do not add CRT here because dependencies will use it incorrectly.
    string(APPEND CMAKE_${lang}_FLAGS " /MP")

    # Debug library for debug configuration.
    string(APPEND CMAKE_${lang}_FLAGS_DEBUG "${CRT}d")

    # All other configurations.
    foreach (config RELEASE RELWITHDEBINFO MINSIZEREL)
      string(APPEND CMAKE_${lang}_FLAGS_${config} ${CRT})
    endforeach ()
  endforeach ()

  # Convenience flags to simplify Windows support in C++ source; used to
  # `#ifdef` out some platform-specific parts of Mesos.  We choose to define
  # a new flag rather than using an existing flag (`_WIN32`) because we want
  # to give the build system fine-grained control over what code is #ifdef'd
  # out in the future.  Using only flags defined by our build system to control
  # this logic is the clearest and most stable way of accomplishing this.
  list(APPEND MESOS_CPPFLAGS -D__WINDOWS__ -DHAVE_LIBZ)

  # Defines to disable warnings generated by Visual Studio when using
  # deprecated functions in CRT and the use of insecure functions in CRT.
  # TODO(dpravat): Once the entire codebase is changed to use secure CRT
  # functions, these defines should be removed.
  list(APPEND MESOS_CPPFLAGS
    -D_SCL_SECURE_NO_WARNINGS
    -D_CRT_SECURE_NO_WARNINGS
    -D_CRT_NONSTDC_NO_WARNINGS
    )

  # Directory structure definitions.
  # TODO(hausdorff): (MESOS-5455) These are placeholder values.
  # Transition away from them.
  set(EXEC_INSTALL_PREFIX     "WARNINGDONOTUSEME")
  set(LIBEXEC_INSTALL_DIR     "WARNINGDONOTUSEME")
  set(PKG_LIBEXEC_INSTALL_DIR "WARNINGDONOTUSEME")
  set(LIB_INSTALL_DIR         "WARNINGDONOTUSEME")
  set(TEST_LIB_EXEC_DIR       "WARNINGDONOTUSEME")
  set(PKG_MODULE_DIR          "WARNINGDONOTUSEME")
  set(S_BIN_DIR               "WARNINGDONOTUSEME")

  # Windows-specific workaround for a glog issue documented here[1].
  # Basically, Windows.h and glog/logging.h both define ERROR. Since we don't
  # need the Windows ERROR, we can use this flag to avoid defining it at all.
  # Unlike the other fix (defining GLOG_NO_ABBREVIATED_SEVERITIES), this fix
  # is guaranteed to require no changes to the original Mesos code. See also
  # the note in the code itself[2].
  #
  # [1] https://google-glog.googlecode.com/svn/trunk/doc/glog.html#windows
  # [2] https://code.google.com/p/google-glog/source/browse/trunk/src/windows/glog/logging.h?r=113
  list(APPEND MESOS_CPPFLAGS -DNOGDI -DNOMINMAX)
endif ()

# GLOBAL CONFIGURATION.
#######################
if (HAS_AUTHENTICATION)
  # NOTE: This conditional is required. It is not sufficient to set
  # `-DHAS_AUTHENTICATION=${HAS_AUTHENTICATION}`, as this will define the
  # symbol, and our intention is to only define it if the CMake variable
  # `HAS_AUTHENTICATION` is set.
  list(APPEND MESOS_CPPFLAGS -DHAS_AUTHENTICATION=1)
endif ()

# Enable the INT64 support for PicoJSON.
# NOTE: PicoJson requires __STDC_FORMAT_MACROS to be defined before importing
# 'inttypes.h'.  Since other libraries may also import this header, it must
# be globally defined so that PicoJson has access to the macros, regardless
# of the order of inclusion.
list(APPEND MESOS_CPPFLAGS -DPICOJSON_USE_INT64 -D__STDC_FORMAT_MACROS)

list(APPEND MESOS_CPPFLAGS
  -DPKGLIBEXECDIR="${PKG_LIBEXEC_INSTALL_DIR}"
  -DLIBDIR="${LIB_INSTALL_DIR}"
  -DVERSION="${PACKAGE_VERSION}"
  -DPKGDATADIR="${DATA_INSTALL_PREFIX}"
  )

if (ENABLE_SSL)
  list(APPEND MESOS_CPPFLAGS -DUSE_SSL_SOCKET=1)
endif ()

# Calculate some build information.
string(TIMESTAMP BUILD_DATE "%Y-%m-%d %H:%M:%S UTC" UTC)
if (WIN32)
  string(TIMESTAMP BUILD_TIME "%s" UTC)
  set(BUILD_USER "$ENV{USERNAME}")
else ()
  execute_process(
    COMMAND date +%s
    OUTPUT_VARIABLE BUILD_TIME
    OUTPUT_STRIP_TRAILING_WHITESPACE
    )
  set(BUILD_USER "$ENV{USER}")
endif ()

# Emit the BUILD_DATE, BUILD_TIME, and BUILD_USER variables into a file.
# This will be updated each time `cmake` is run.
configure_file(
  "${CMAKE_SOURCE_DIR}/src/common/build_config.hpp.in"
  "${CMAKE_BINARY_DIR}/src/common/build_config.hpp"
  @ONLY
  )

# TODO(hausdorff): (MESOS-5902) Populate this value when we integrate Java
# support.
set(BUILD_JAVA_JVM_LIBRARY "")

# NOTE: The quotes in these definitions are necessary. Without them, the
# preprocessor will interpret the symbols as (e.g.) int literals and uquoted
# identifiers, rather than the string values our code expects.
list(APPEND MESOS_CPPFLAGS
  -DUSE_STATIC_LIB
  -DUSE_CMAKE_BUILD_CONFIG
  -DBUILD_JAVA_JVM_LIBRARY="${BUILD_JAVA_JVM_LIBRARY}"
  )

# TODO(hausdorff): (MESOS-5455) `BUILD_FLAGS` is currently a placeholder value.
add_definitions(${MESOS_CPPFLAGS} -DBUILD_FLAGS="")
