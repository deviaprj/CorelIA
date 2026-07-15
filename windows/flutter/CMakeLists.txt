cmake_minimum_required(VERSION 3.14)
set(EPHEMERAL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ephemeral")

# Flutter library and tool build rules.
list(APPEND CMAKE_MODULE_PATH "${EPHEMERAL_DIR}")

# Generated plugin registrant.
set(GENERATED_PLUGIN_REGISTRANT
  "${EPHEMERAL_DIR}/generated_plugin_registrant.cc"
  "${EPHEMERAL_DIR}/generated_plugin_registrant.h"
  "${EPHEMERAL_DIR}/generated_plugins.cmake"
)

# Configuration provided via flutter tool.
include(${EPHEMERAL_DIR}/generated_config.cmake)

# Targets for flutter wrapper.
set(FLUTTER_WRAPPER_ROOT "${EPHEMERAL_DIR}/cpp_client_wrapper")
include(${FLUTTER_WRAPPER_ROOT}/flutter_wrapper.cmake)

# === Flutter Library ===
set(FLUTTER_LIBRARY "${FLUTTER_DIR}/flutter_windows.dll")

# Published library variables.
set(FLUTTER_LIBRARY ${FLUTTER_LIBRARY} PARENT_SCOPE)
set(FLUTTER_ICU_DATA_FILE "${FLUTTER_DIR}/icudtl.dat" PARENT_SCOPE)
set(AOT_LIBRARY "${AOT_LIBRARY}" PARENT_SCOPE)
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/" PARENT_SCOPE)
set(PLUGIN_BUNDLED_LIBRARIES "" PARENT_SCOPE)

# Generated plugin config.
if(EXISTS "${EPHEMERAL_DIR}/generated_plugins.cmake")
  include("${EPHEMERAL_DIR}/generated_plugins.cmake")
endif()

# === Flutter assemble ===
add_custom_target(flutter_assemble
  COMMAND ${CMAKE_COMMAND} -E echo "Flutter assemble step — run flutter build windows to populate ephemeral/"
)
