cmake_minimum_required(VERSION 3.20)
project(NextPhoto LANGUAGES C CXX OBJCXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SD_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SD_METAL ON CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
set(GGML_METAL_USE_BF16 OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
add_subdirectory(stable-diffusion.cpp)
# Objective-C class names are process-global even when C symbols are hidden.
target_compile_definitions(ggml-metal PRIVATE GGMLMetalClass=NextPhotoGGMLMetalClass)
add_library(NextPhoto SHARED NextPhoto.mm)
target_compile_options(NextPhoto PRIVATE -fobjc-arc)
target_link_libraries(NextPhoto PRIVATE stable-diffusion "-framework UIKit" "-framework CoreGraphics" "-framework CoreFoundation")
# Each engine uses its pinned GGML internally; expose only our bridge symbol.
target_link_options(NextPhoto PRIVATE "-Wl,-exported_symbol,_NextPhotoGenerate")
set_target_properties(NextPhoto PROPERTIES FRAMEWORK TRUE
 MACOSX_FRAMEWORK_IDENTIFIER "cc.nextsolution.nextai.photoengine"
 XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
 XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "cc.nextsolution.nextai.photoengine"
 MACOSX_RPATH ON INSTALL_NAME_DIR "@rpath" BUILD_WITH_INSTALL_NAME_DIR TRUE
 LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/framework")
