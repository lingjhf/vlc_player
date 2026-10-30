# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "vlc_player")
project(${PROJECT_NAME} LANGUAGES CXX)

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "vlc_player_plugin")

# Any new source files that you add to the plugin should be added here.
list(APPEND PLUGIN_SOURCES
  "../src/native/vlc_player_core.cc"
  "../src/native/vlc_player_core.h"
  "../src/native/vlc_player_types.h"
  "vlc_player_plugin.cpp"
  "vlc_player_plugin.h"
  "windows_player_task_runner.h"
)

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
add_library(${PLUGIN_NAME} SHARED
  "include/vlc_player/vlc_player_plugin_c_api.h"
  "vlc_player_plugin_c_api.cpp"
  ${PLUGIN_SOURCES}
)

# Apply a standard set of build settings that are configured in the
# application-level CMakeLists.txt. This can be removed for plugins that want
# full control over build settings.
apply_standard_settings(${PLUGIN_NAME})

# Symbols are hidden by default to reduce the chance of accidental conflicts
# between plugins. This should not be removed; any symbols that should be
# exported should be explicitly exported with the FLUTTER_PLUGIN_EXPORT macro.
set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

# Source include directories and library dependencies. Add any plugin-specific
# dependencies here.
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "vlc_player currently supports Windows x64 builds only.")
endif()

set(VLC_PLAYER_VLC_VERSION "3.0.21")
set(VLC_PLAYER_VLC_ARCHIVE "vlc-${VLC_PLAYER_VLC_VERSION}-win64.7z")
set(VLC_PLAYER_VLC_URL
  "https://download.videolan.org/pub/videolan/vlc/${VLC_PLAYER_VLC_VERSION}/win64/${VLC_PLAYER_VLC_ARCHIVE}")
set(VLC_PLAYER_VLC_SHA256
  "9d2b24d6bc4196b3da8d181a3878678ba272e2a7690321f8826da76a69b2fb9c")
set(VLC_PLAYER_VLC_DOWNLOAD_DIR "${CMAKE_CURRENT_BINARY_DIR}/vlc")
set(VLC_PLAYER_VLC_ARCHIVE_PATH
  "${VLC_PLAYER_VLC_DOWNLOAD_DIR}/${VLC_PLAYER_VLC_ARCHIVE}")
set(VLC_PLAYER_RUNTIME_DIR
  "${VLC_PLAYER_VLC_DOWNLOAD_DIR}/vlc-${VLC_PLAYER_VLC_VERSION}")

if(NOT EXISTS "${VLC_PLAYER_RUNTIME_DIR}/libvlc.dll" OR
   NOT EXISTS "${VLC_PLAYER_RUNTIME_DIR}/libvlccore.dll" OR
   NOT EXISTS "${VLC_PLAYER_RUNTIME_DIR}/plugins")
  message(STATUS "Downloading VLC ${VLC_PLAYER_VLC_VERSION} Windows runtime")
  file(MAKE_DIRECTORY "${VLC_PLAYER_VLC_DOWNLOAD_DIR}")
  file(DOWNLOAD
    "${VLC_PLAYER_VLC_URL}"
    "${VLC_PLAYER_VLC_ARCHIVE_PATH}"
    EXPECTED_HASH "SHA256=${VLC_PLAYER_VLC_SHA256}"
    SHOW_PROGRESS
    STATUS vlc_player_download_status
    TLS_VERIFY ON)
  list(GET vlc_player_download_status 0 vlc_player_download_code)
  list(GET vlc_player_download_status 1 vlc_player_download_message)
  if(NOT vlc_player_download_code EQUAL 0)
    message(FATAL_ERROR
      "Failed to download VLC Windows runtime from ${VLC_PLAYER_VLC_URL}: "
      "${vlc_player_download_message}")
  endif()

  file(REMOVE_RECURSE "${VLC_PLAYER_RUNTIME_DIR}")
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xzf "${VLC_PLAYER_VLC_ARCHIVE_PATH}"
    WORKING_DIRECTORY "${VLC_PLAYER_VLC_DOWNLOAD_DIR}"
    RESULT_VARIABLE vlc_player_extract_result)
  if(NOT vlc_player_extract_result EQUAL 0)
    message(FATAL_ERROR
      "Failed to extract VLC Windows runtime from ${VLC_PLAYER_VLC_ARCHIVE_PATH}.")
  endif()
endif()

# VLC 3.0.21 rejects valid multichannel Opus and some Speex headers, and its
# libavcodec lacks interlaced VP5 decoding.
# Use the fixed official 3.0.24 decoder modules with the same 3.0 plugin ABI,
# while retaining the 3.0.21 runtime's other decoder and access modules.
set(VLC_PLAYER_DECODER_VERSION "3.0.24")
set(VLC_PLAYER_DECODER_ARCHIVE "vlc-${VLC_PLAYER_DECODER_VERSION}-win64.7z")
set(VLC_PLAYER_DECODER_ARCHIVE_PATH "${VLC_PLAYER_VLC_DOWNLOAD_DIR}/${VLC_PLAYER_DECODER_ARCHIVE}")
set(VLC_PLAYER_DECODER_ARCHIVE_SHA256
  "1ed59c09152e78aff84663fa76efab26057716576db74332858810e5ef54ae1f")
set(VLC_PLAYER_OPUS_MODULE
  "${VLC_PLAYER_VLC_DOWNLOAD_DIR}/vlc-${VLC_PLAYER_DECODER_VERSION}/plugins/codec/libopus_plugin.dll")
set(VLC_PLAYER_OPUS_MODULE_SHA256
  "88e936a71b814c390792e28b346d090b49cdf2a1dec1c5d632acd58566fc7815")
set(VLC_PLAYER_SPEEX_MODULE
  "${VLC_PLAYER_VLC_DOWNLOAD_DIR}/vlc-${VLC_PLAYER_DECODER_VERSION}/plugins/codec/libspeex_plugin.dll")
set(VLC_PLAYER_SPEEX_MODULE_SHA256
  "d7db3d56bd0c68045021ac76acc52b14c71a1714c1552430f1a4939ba4d4449c")
set(VLC_PLAYER_AVCODEC_MODULE
  "${VLC_PLAYER_VLC_DOWNLOAD_DIR}/vlc-${VLC_PLAYER_DECODER_VERSION}/plugins/codec/libavcodec_plugin.dll")
set(VLC_PLAYER_AVCODEC_MODULE_SHA256
  "f8af2239f1a1fa99e2b808af852e87a72447c51134a96bfe4ef538629702744e")
set(vlc_player_opus_valid FALSE)
if(EXISTS "${VLC_PLAYER_OPUS_MODULE}")
  file(SHA256 "${VLC_PLAYER_OPUS_MODULE}" vlc_player_opus_hash)
  if(vlc_player_opus_hash STREQUAL VLC_PLAYER_OPUS_MODULE_SHA256)
    set(vlc_player_opus_valid TRUE)
  endif()
endif()
set(vlc_player_speex_valid FALSE)
if(EXISTS "${VLC_PLAYER_SPEEX_MODULE}")
  file(SHA256 "${VLC_PLAYER_SPEEX_MODULE}" vlc_player_speex_hash)
  if(vlc_player_speex_hash STREQUAL VLC_PLAYER_SPEEX_MODULE_SHA256)
    set(vlc_player_speex_valid TRUE)
  endif()
endif()
set(vlc_player_avcodec_valid FALSE)
if(EXISTS "${VLC_PLAYER_AVCODEC_MODULE}")
  file(SHA256 "${VLC_PLAYER_AVCODEC_MODULE}" vlc_player_avcodec_hash)
  if(vlc_player_avcodec_hash STREQUAL VLC_PLAYER_AVCODEC_MODULE_SHA256)
    set(vlc_player_avcodec_valid TRUE)
  endif()
endif()
if(NOT vlc_player_opus_valid OR NOT vlc_player_speex_valid OR NOT vlc_player_avcodec_valid)
  message(STATUS "Downloading VLC ${VLC_PLAYER_DECODER_VERSION} decoder modules")
  file(MAKE_DIRECTORY "${VLC_PLAYER_VLC_DOWNLOAD_DIR}")
  file(DOWNLOAD
    "https://download.videolan.org/pub/videolan/vlc/${VLC_PLAYER_DECODER_VERSION}/win64/${VLC_PLAYER_DECODER_ARCHIVE}"
    "${VLC_PLAYER_DECODER_ARCHIVE_PATH}"
    EXPECTED_HASH "SHA256=${VLC_PLAYER_DECODER_ARCHIVE_SHA256}"
    SHOW_PROGRESS STATUS vlc_player_decoder_download_status TLS_VERIFY ON)
  list(GET vlc_player_decoder_download_status 0 vlc_player_decoder_download_code)
  list(GET vlc_player_decoder_download_status 1 vlc_player_decoder_download_message)
  if(NOT vlc_player_decoder_download_code EQUAL 0)
    message(FATAL_ERROR "Failed to download VLC decoder modules: ${vlc_player_decoder_download_message}")
  endif()
  execute_process(
    COMMAND "${CMAKE_COMMAND}" -E tar xf "${VLC_PLAYER_DECODER_ARCHIVE_PATH}"
      "vlc-${VLC_PLAYER_DECODER_VERSION}/plugins/codec/libopus_plugin.dll"
      "vlc-${VLC_PLAYER_DECODER_VERSION}/plugins/codec/libspeex_plugin.dll"
      "vlc-${VLC_PLAYER_DECODER_VERSION}/plugins/codec/libavcodec_plugin.dll"
    WORKING_DIRECTORY "${VLC_PLAYER_VLC_DOWNLOAD_DIR}"
    RESULT_VARIABLE vlc_player_decoder_extract_result)
  file(REMOVE "${VLC_PLAYER_DECODER_ARCHIVE_PATH}")
  if(NOT vlc_player_decoder_extract_result EQUAL 0 OR NOT EXISTS "${VLC_PLAYER_OPUS_MODULE}" OR NOT EXISTS "${VLC_PLAYER_SPEEX_MODULE}" OR NOT EXISTS "${VLC_PLAYER_AVCODEC_MODULE}")
    message(FATAL_ERROR "Failed to extract VLC decoder modules.")
  endif()
  file(SHA256 "${VLC_PLAYER_OPUS_MODULE}" vlc_player_opus_hash)
  if(NOT vlc_player_opus_hash STREQUAL VLC_PLAYER_OPUS_MODULE_SHA256)
    message(FATAL_ERROR "VLC Opus module checksum mismatch.")
  endif()
  file(SHA256 "${VLC_PLAYER_SPEEX_MODULE}" vlc_player_speex_hash)
  if(NOT vlc_player_speex_hash STREQUAL VLC_PLAYER_SPEEX_MODULE_SHA256)
    message(FATAL_ERROR "VLC Speex module checksum mismatch.")
  endif()
  file(SHA256 "${VLC_PLAYER_AVCODEC_MODULE}" vlc_player_avcodec_hash)
  if(NOT vlc_player_avcodec_hash STREQUAL VLC_PLAYER_AVCODEC_MODULE_SHA256)
    message(FATAL_ERROR "VLC libavcodec module checksum mismatch.")
  endif()
endif()

# The bundled MMDevice module gives each live player its own reusable Windows
# audio session, preventing one player's volume or mute from affecting another.
# Source, licenses and reproducible build instructions are included alongside it.
set(VLC_PLAYER_MMDEVICE_MODULE
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/vlc_mmdevice/bin/x64/libmmdevice_plugin.dll")
set(VLC_PLAYER_MMDEVICE_MODULE_SHA256
  "0d5b36ad46e68bdfb3a772c21169f1fc2f0d3fc64f8819e0794295b4ef5791a9")
if(NOT EXISTS "${VLC_PLAYER_MMDEVICE_MODULE}")
  message(FATAL_ERROR "Missing Windows MMDevice module: ${VLC_PLAYER_MMDEVICE_MODULE}")
endif()
file(SHA256 "${VLC_PLAYER_MMDEVICE_MODULE}" vlc_player_mmdevice_hash)
if(NOT vlc_player_mmdevice_hash STREQUAL VLC_PLAYER_MMDEVICE_MODULE_SHA256)
  message(FATAL_ERROR "Windows MMDevice module checksum mismatch.")
endif()

# Use the standard default DVB subtitle palette when no CLUT was transmitted.
# Source, licenses and reproducible build instructions accompany the module.
set(VLC_PLAYER_DVBSUB_MODULE
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/vlc_dvbsub/bin/x64/libdvbsub_plugin.dll")
set(VLC_PLAYER_DVBSUB_MODULE_SHA256
  "1d34ca937959ab874729fd59f0d2131eccab3c743b03677d6eeab6729d1252f6")
if(NOT EXISTS "${VLC_PLAYER_DVBSUB_MODULE}")
  message(FATAL_ERROR "Missing Windows DVB subtitle module: ${VLC_PLAYER_DVBSUB_MODULE}")
endif()
file(SHA256 "${VLC_PLAYER_DVBSUB_MODULE}" vlc_player_dvbsub_hash)
if(NOT vlc_player_dvbsub_hash STREQUAL VLC_PLAYER_DVBSUB_MODULE_SHA256)
  message(FATAL_ERROR "Windows DVB subtitle module checksum mismatch.")
endif()

# VLC 3.0.21's native VC-1 demuxer is normally forced-only. Enable a
# conservative probe for advanced-profile .vc1 elementary streams.
set(VLC_PLAYER_VC1_MODULE
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/vlc_vc1/bin/x64/libvc1_plugin.dll")
if(NOT EXISTS "${VLC_PLAYER_VC1_MODULE}")
  message(FATAL_ERROR "Missing Windows VC-1 module: ${VLC_PLAYER_VC1_MODULE}")
endif()
file(SHA256 "${VLC_PLAYER_VC1_MODULE}" vlc_player_vc1_hash)
if(NOT vlc_player_vc1_hash STREQUAL "35041c27e49932f559812063f148a6784d0e0c82a6d9d9279d3bfa48d72d3d55")
  message(FATAL_ERROR "Windows VC-1 module checksum mismatch.")
endif()

# Report relative playback time for the existing PVA demuxer.
set(VLC_PLAYER_PVA_MODULE
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/vlc_pva/bin/x64/libpva_plugin.dll")
if(NOT EXISTS "${VLC_PLAYER_PVA_MODULE}")
  message(FATAL_ERROR "Missing Windows PVA module: ${VLC_PLAYER_PVA_MODULE}")
endif()
file(SHA256 "${VLC_PLAYER_PVA_MODULE}" vlc_player_pva_hash)
if(NOT vlc_player_pva_hash STREQUAL "8985ac57bd54652a77c6efc28ff724699524117c1e41cb50ad0b96ec095129ed")
  message(FATAL_ERROR "Windows PVA module checksum mismatch.")
endif()

# Use the current OGM subtitle granule as its presentation timestamp.
set(VLC_PLAYER_OGG_MODULE
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/vlc_ogg/bin/x64/libogg_plugin.dll")
if(NOT EXISTS "${VLC_PLAYER_OGG_MODULE}")
  message(FATAL_ERROR "Missing Windows Ogg module: ${VLC_PLAYER_OGG_MODULE}")
endif()
file(SHA256 "${VLC_PLAYER_OGG_MODULE}" vlc_player_ogg_hash)
if(NOT vlc_player_ogg_hash STREQUAL "705b091683075d7aac22ef04c42bc3d5239a8b69f54c43df9cea8d87a2de9d09")
  message(FATAL_ERROR "Windows Ogg module checksum mismatch.")
endif()

# Decode raw Shorten streams and derive timestamps from decoded samples.
set(VLC_PLAYER_SHORTEN_MODULE
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/vlc_shorten/bin/x64/libshorten_plugin.dll")
if(NOT EXISTS "${VLC_PLAYER_SHORTEN_MODULE}")
  message(FATAL_ERROR "Missing Windows Shorten module: ${VLC_PLAYER_SHORTEN_MODULE}")
endif()
file(SHA256 "${VLC_PLAYER_SHORTEN_MODULE}" vlc_player_shorten_hash)
if(NOT vlc_player_shorten_hash STREQUAL "6b7bb4fdba4f468c6d4609e34dd87316fc0371d2443d616d2d3236a5f1990784")
  message(FATAL_ERROR "Windows Shorten module checksum mismatch.")
endif()

# OpenMPT extends tracker support while keeping VLC's original MOD module as
# a fallback. The archive and every selected binary are verified before use.
set(VLC_PLAYER_OPENMPT_MODULE
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/vlc_openmpt/bin/x64/libopenmptmod_plugin.dll")
if(NOT EXISTS "${VLC_PLAYER_OPENMPT_MODULE}")
  message(FATAL_ERROR "Missing Windows OpenMPT module: ${VLC_PLAYER_OPENMPT_MODULE}")
endif()
file(SHA256 "${VLC_PLAYER_OPENMPT_MODULE}" vlc_player_openmpt_module_hash)
if(NOT vlc_player_openmpt_module_hash STREQUAL "287ecd6530db89329b3372cd2e27ebb649601c370edc64990e53e80c06950094")
  message(FATAL_ERROR "Windows OpenMPT module checksum mismatch.")
endif()
set(VLC_PLAYER_OPENMPT_DIR "${VLC_PLAYER_VLC_DOWNLOAD_DIR}/openmpt-0.8.9")
set(VLC_PLAYER_OPENMPT_ARCHIVE "${VLC_PLAYER_VLC_DOWNLOAD_DIR}/openmpt-0.8.9.zip")
set(VLC_PLAYER_OPENMPT_FILES libopenmpt.dll openmpt-mpg123.dll openmpt-ogg.dll openmpt-vorbis.dll openmpt-zlib.dll)
set(VLC_PLAYER_OPENMPT_HASHES
  9fa3131204f44a3b157f22f9f0ae11c5cccb5befa37e91a2476567aa0f4b0d94
  f15edd24576d88fa08a153c4a7f9d9d7956449e4fc67758d660ad35d9e1696df
  bbeea26588404a00ae964f1c4aceb6d6474e5885f8337491a4c69e29e8516eb6
  7393d017e2930d57c12c016de21c6fa658f862481758ba394823f6ac5e013df2
  966d96e9aaf5cbd9e1b600435af1180a3a643ace17a0e782a5becf378b25445b)
set(vlc_player_openmpt_valid TRUE)
foreach(index RANGE 0 4)
  list(GET VLC_PLAYER_OPENMPT_FILES ${index} filename)
  list(GET VLC_PLAYER_OPENMPT_HASHES ${index} expected_hash)
  set(path "${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/${filename}")
  if(EXISTS "${path}")
    file(SHA256 "${path}" actual_hash)
    if(NOT actual_hash STREQUAL expected_hash)
      set(vlc_player_openmpt_valid FALSE)
    endif()
  else()
    set(vlc_player_openmpt_valid FALSE)
  endif()
endforeach()
if(NOT vlc_player_openmpt_valid)
  message(STATUS "Downloading libopenmpt 0.8.9 Windows runtime")
  file(MAKE_DIRECTORY "${VLC_PLAYER_OPENMPT_DIR}")
  file(DOWNLOAD
    "https://lib.openmpt.org/files/libopenmpt/dev/libopenmpt-0.8.9%2Brelease.dev.windows.vs2022.zip"
    "${VLC_PLAYER_OPENMPT_ARCHIVE}"
    EXPECTED_HASH "SHA256=a23e375e576e3a6997ffeeb6cf34488e9020e2a5d8226856b02628b6a87c5e8e"
    STATUS openmpt_download_status TLS_VERIFY ON SHOW_PROGRESS)
  list(GET openmpt_download_status 0 openmpt_download_code)
  if(NOT openmpt_download_code EQUAL 0)
    list(GET openmpt_download_status 1 openmpt_download_message)
    message(FATAL_ERROR "Failed to download libopenmpt: ${openmpt_download_message}")
  endif()
  set(openmpt_archive_members)
  foreach(filename ${VLC_PLAYER_OPENMPT_FILES})
    list(APPEND openmpt_archive_members "bin/amd64/${filename}")
  endforeach()
  execute_process(COMMAND "${CMAKE_COMMAND}" -E tar xf "${VLC_PLAYER_OPENMPT_ARCHIVE}" ${openmpt_archive_members}
    WORKING_DIRECTORY "${VLC_PLAYER_OPENMPT_DIR}" RESULT_VARIABLE openmpt_extract_result)
  file(REMOVE "${VLC_PLAYER_OPENMPT_ARCHIVE}")
  if(NOT openmpt_extract_result EQUAL 0)
    message(FATAL_ERROR "Failed to extract libopenmpt runtime.")
  endif()
endif()
foreach(index RANGE 0 4)
  list(GET VLC_PLAYER_OPENMPT_FILES ${index} filename)
  list(GET VLC_PLAYER_OPENMPT_HASHES ${index} expected_hash)
  file(SHA256 "${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/${filename}" actual_hash)
  if(NOT actual_hash STREQUAL expected_hash)
    message(FATAL_ERROR "libopenmpt runtime checksum mismatch: ${filename}")
  endif()
endforeach()
# The private name avoids resolving this import to another plugin's libopenmpt.
configure_file("${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/libopenmpt.dll"
  "${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/vlc_player_openmpt_0_8.dll" COPYONLY)

set(VLC_PLAYER_LIBVLC_MEDIA_HEADER
  "${VLC_PLAYER_RUNTIME_DIR}/sdk/include/vlc/libvlc_media.h")
if(EXISTS "${VLC_PLAYER_LIBVLC_MEDIA_HEADER}")
  file(READ "${VLC_PLAYER_LIBVLC_MEDIA_HEADER}" vlc_player_libvlc_media)
  set(vlc_player_libvlc_media_patched "${vlc_player_libvlc_media}")
  string(REPLACE
    "typedef SSIZE_T ssize_t;"
    "#if _MSC_VER < 1900\ntypedef SSIZE_T ssize_t;\n#endif"
    vlc_player_libvlc_media_patched
    "${vlc_player_libvlc_media_patched}")
  string(REPLACE
    "#ifndef _SSIZE_T_DEFINED\n#define _SSIZE_T_DEFINED\ntypedef SSIZE_T ssize_t;\n#endif"
    "#if _MSC_VER < 1900\ntypedef SSIZE_T ssize_t;\n#endif"
    vlc_player_libvlc_media_patched
    "${vlc_player_libvlc_media_patched}")
  if(NOT vlc_player_libvlc_media STREQUAL vlc_player_libvlc_media_patched)
    file(WRITE "${VLC_PLAYER_LIBVLC_MEDIA_HEADER}"
      "${vlc_player_libvlc_media_patched}")
  endif()
endif()

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(vlc_player_bundled_libraries
  ""
  PARENT_SCOPE
)
if(EXISTS "${VLC_PLAYER_RUNTIME_DIR}/libvlc.dll" AND
   EXISTS "${VLC_PLAYER_RUNTIME_DIR}/libvlccore.dll" AND
   EXISTS "${VLC_PLAYER_RUNTIME_DIR}/plugins" AND
   EXISTS "${VLC_PLAYER_RUNTIME_DIR}/sdk/include/vlc/vlc.h" AND
   EXISTS "${VLC_PLAYER_RUNTIME_DIR}/sdk/lib/libvlc.lib")
  target_include_directories(${PLUGIN_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../src/native"
    "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvlcpp"
    "${VLC_PLAYER_RUNTIME_DIR}/sdk/include")
  target_link_libraries(${PLUGIN_NAME} PRIVATE
    "${VLC_PLAYER_RUNTIME_DIR}/sdk/lib/libvlc.lib")

  file(GLOB VLC_PLAYER_RUNTIME_DLLS "${VLC_PLAYER_RUNTIME_DIR}/*.dll")
  list(APPEND VLC_PLAYER_RUNTIME_DLLS
    "${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/vlc_player_openmpt_0_8.dll"
    "${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/openmpt-mpg123.dll"
    "${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/openmpt-ogg.dll"
    "${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/openmpt-vorbis.dll"
    "${VLC_PLAYER_OPENMPT_DIR}/bin/amd64/openmpt-zlib.dll")
  set(vlc_player_bundled_libraries
    ${VLC_PLAYER_RUNTIME_DLLS}
    PARENT_SCOPE
  )

  if(DEFINED BINARY_NAME)
    foreach(vlc_player_runtime_directory hrtfs locale lua plugins skins)
      if(EXISTS "${VLC_PLAYER_RUNTIME_DIR}/${vlc_player_runtime_directory}")
        if(vlc_player_runtime_directory STREQUAL "plugins")
          # The bundled Schroedinger Dirac decoder crashes on valid VC-2 and
          # Dirac inputs. Libavcodec provides the decoder instead, as in VLC's
          # upstream removal: https://mailman.videolan.org/pipermail/vlc-commits/2026-January/072517.html
          add_custom_target(
            ${PLUGIN_NAME}_copy_${vlc_player_runtime_directory} ALL
            COMMAND "${CMAKE_COMMAND}" -E copy_directory
            "${VLC_PLAYER_RUNTIME_DIR}/${vlc_player_runtime_directory}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/${vlc_player_runtime_directory}"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_OPUS_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/codec/libopus_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_SPEEX_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/codec/libspeex_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_AVCODEC_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/codec/libavcodec_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_DVBSUB_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/codec/libdvbsub_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_MMDEVICE_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/audio_output/libmmdevice_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_OPENMPT_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/demux/libopenmptmod_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_VC1_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/demux/libvc1_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_PVA_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/demux/libpva_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_OGG_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/demux/libogg_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${VLC_PLAYER_SHORTEN_MODULE}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/demux/libshorten_plugin.dll"
            COMMAND "${CMAKE_COMMAND}" -E remove -f
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/plugins/codec/libschroedinger_plugin.dll")
        else()
          add_custom_target(
            ${PLUGIN_NAME}_copy_${vlc_player_runtime_directory} ALL
            COMMAND "${CMAKE_COMMAND}" -E copy_directory
            "${VLC_PLAYER_RUNTIME_DIR}/${vlc_player_runtime_directory}"
            "$<TARGET_FILE_DIR:${BINARY_NAME}>/${vlc_player_runtime_directory}")
        endif()
      endif()
    endforeach()
  endif()
else()
  message(FATAL_ERROR
    "Incomplete downloaded VLC Windows runtime in ${VLC_PLAYER_RUNTIME_DIR}. "
    "Expected libvlc.dll, libvlccore.dll, plugins/, sdk/include, and "
    "sdk/lib/libvlc.lib.")
endif()

# === Tests ===
# These unit tests can be run from a terminal after building the example, or
# from Visual Studio after opening the generated solution file.

# Only enable test builds when building the example (which sets this variable)
# so that plugin clients aren't building the tests.
if (${include_${PROJECT_NAME}_tests})
set(TEST_RUNNER "${PROJECT_NAME}_test")
enable_testing()

# Add the Google Test dependency.
include(FetchContent)
FetchContent_Declare(
  googletest
  URL https://github.com/google/googletest/archive/refs/tags/v1.17.0.zip
  DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
# Prevent overriding the parent project's compiler/linker settings
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
# Disable install commands for gtest so it doesn't end up in the bundle.
set(INSTALL_GTEST OFF CACHE BOOL "Disable installation of googletest" FORCE)
FetchContent_MakeAvailable(googletest)

# The plugin's C API is not very useful for unit testing, so build the sources
# directly into the test binary rather than using the DLL.
add_executable(${TEST_RUNNER}
  test/vlc_player_plugin_test.cpp
  test/vlc_player_lifecycle_test.cpp
  ${PLUGIN_SOURCES}
)
apply_standard_settings(${TEST_RUNNER})
target_compile_definitions(${TEST_RUNNER} PRIVATE VLC_PLAYER_TESTING)
target_compile_definitions(${TEST_RUNNER} PRIVATE
  VLC_PLAYER_TEST_MEDIA_PATH="${CMAKE_CURRENT_SOURCE_DIR}/../example/assets/format_fixtures/video.mp4")
target_include_directories(${TEST_RUNNER} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(${TEST_RUNNER} PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src/native"
  "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvlcpp"
  "${VLC_PLAYER_RUNTIME_DIR}/sdk/include")
target_link_libraries(${TEST_RUNNER} PRIVATE flutter_wrapper_plugin)
target_link_libraries(${TEST_RUNNER} PRIVATE
  "${VLC_PLAYER_RUNTIME_DIR}/sdk/lib/libvlc.lib")
target_link_libraries(${TEST_RUNNER} PRIVATE gtest_main gmock)
# flutter_wrapper_plugin has link dependencies on the Flutter DLL.
add_custom_command(TARGET ${TEST_RUNNER} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "${FLUTTER_LIBRARY}" $<TARGET_FILE_DIR:${TEST_RUNNER}>
)
foreach(vlc_player_runtime_dll ${VLC_PLAYER_RUNTIME_DLLS})
  add_custom_command(TARGET ${TEST_RUNNER} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
    "${vlc_player_runtime_dll}" $<TARGET_FILE_DIR:${TEST_RUNNER}>
  )
endforeach()
foreach(vlc_player_runtime_directory hrtfs locale lua plugins skins)
  if(EXISTS "${VLC_PLAYER_RUNTIME_DIR}/${vlc_player_runtime_directory}")
    add_custom_command(TARGET ${TEST_RUNNER} POST_BUILD
      COMMAND "${CMAKE_COMMAND}" -E copy_directory
      "${VLC_PLAYER_RUNTIME_DIR}/${vlc_player_runtime_directory}"
      "$<TARGET_FILE_DIR:${TEST_RUNNER}>/${vlc_player_runtime_directory}")
  endif()
endforeach()
add_custom_command(TARGET ${TEST_RUNNER} POST_BUILD
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_OPUS_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/codec/libopus_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_SPEEX_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/codec/libspeex_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_AVCODEC_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/codec/libavcodec_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_DVBSUB_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/codec/libdvbsub_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_MMDEVICE_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/audio_output/libmmdevice_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_OPENMPT_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/demux/libopenmptmod_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_VC1_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/demux/libvc1_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_PVA_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/demux/libpva_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_OGG_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/demux/libogg_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
  "${VLC_PLAYER_SHORTEN_MODULE}"
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/demux/libshorten_plugin.dll"
  COMMAND "${CMAKE_COMMAND}" -E remove -f
  "$<TARGET_FILE_DIR:${TEST_RUNNER}>/plugins/codec/libschroedinger_plugin.dll")

# Enable automatic test discovery.
include(GoogleTest)
gtest_discover_tests(${TEST_RUNNER} DISCOVERY_TIMEOUT 60)
endif()
