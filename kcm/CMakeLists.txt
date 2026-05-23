cmake_minimum_required(VERSION 3.20)
project(kcm_dropdown_any)

find_package(ECM 6.0 REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH} ${CMAKE_MODULE_PATH})

include(KDEInstallDirs6)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)

find_package(Qt6 REQUIRED COMPONENTS Core Quick)
find_package(KF6 REQUIRED COMPONENTS KCMUtils Config CoreAddons)
find_package(KWayland REQUIRED)

qt_add_resources(QML_RESOURCES kcm_resources.qrc)

kcoreaddons_add_plugin(kcm_dropdown_any
    SOURCES kcm_dropdown_any.cpp ${QML_RESOURCES}
    INSTALL_NAMESPACE kwin/effects/configs
)

target_link_libraries(kcm_dropdown_any
    Qt6::Core
    Qt6::Quick
    KF6::KCMUtils
    KF6::ConfigCore
    KF6::CoreAddons
    Plasma::KWaylandClient
)
