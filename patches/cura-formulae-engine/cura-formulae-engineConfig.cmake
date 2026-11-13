# Minimal CMake package configuration for CuraFormulaeEngine.
#
# Upstream only ships a Conan recipe, so the Dockerfile installs this file next
# to the library. CuraEngine's `find_package(cura-formulae-engine REQUIRED)`
# expects the imported target name used below.

include(CMakeFindDependencyMacro)
find_dependency(fmt)
find_dependency(spdlog)
find_dependency(range-v3)
find_dependency(zeus_expected)
find_dependency(lexy)

if(NOT TARGET cura-formulae-engine::cura-formulae-engine)
    get_filename_component(_cfe_prefix "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
    add_library(cura-formulae-engine::cura-formulae-engine SHARED IMPORTED)
    set_target_properties(cura-formulae-engine::cura-formulae-engine PROPERTIES
        IMPORTED_LOCATION "${_cfe_prefix}/lib/libcura-formulae-engine.so"
        INTERFACE_INCLUDE_DIRECTORIES "${_cfe_prefix}/include"
        INTERFACE_LINK_LIBRARIES "fmt::fmt;spdlog::spdlog;range-v3::range-v3;zeus::expected;foonathan::lexy")
endif()
