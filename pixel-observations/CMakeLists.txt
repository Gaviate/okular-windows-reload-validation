cmake_minimum_required(VERSION 3.20)
project(OkularReplacementPixels LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Widgets)
add_executable(okular-replacement-pixels main.cpp)
target_include_directories(okular-replacement-pixels PRIVATE
    "${KCOREADDONS_SOURCE}/src/lib/plugin"
    "${KCOREADDONS_BUILD}/src/lib")
target_link_libraries(okular-replacement-pixels PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets "${KCOREADDONS_BUILD}/lib/KF6CoreAddons.lib")
