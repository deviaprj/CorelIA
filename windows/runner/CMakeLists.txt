cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

if(MSVC)
  set_target_properties(${BINARY_NAME} PROPERTIES
    WIN32_EXECUTABLE YES
  )
endif()

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

apply_standard_settings(${BINARY_NAME})

target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE d3d11 dxgi dxguid dwmapi shcore windowscodecs)

add_dependencies(${BINARY_NAME} flutter_assemble)

set_target_properties(${BINARY_NAME} PROPERTIES
  OUTPUT_NAME "corely"
)
