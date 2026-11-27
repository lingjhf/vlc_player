cmake_minimum_required(VERSION 3.22.1)
project(vlc_player_transport LANGUAGES CXX)

add_library(vlc_player_transport SHARED
  vlc_player_transport.cc
  dvd_video_size.cc
)
target_compile_features(vlc_player_transport PRIVATE cxx_std_17)
target_link_libraries(vlc_player_transport PRIVATE dl)
target_include_directories(vlc_player_transport PRIVATE
  "${DART_SDK_INCLUDE}"
  "${CMAKE_CURRENT_SOURCE_DIR}/../../../../src/native"
)
