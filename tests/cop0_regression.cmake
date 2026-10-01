# Inject with -DCMAKE_PROJECT_INCLUDE=/absolute/path/tests/cop0_regression.cmake
# into the pinned PS2Recomp root configuration, with only PS2X_BUILD_RECOMP=ON.
include_guard(GLOBAL)
set(_cop0_test_root "${CMAKE_CURRENT_LIST_DIR}")
add_executable(cop0_fixture_generator "${_cop0_test_root}/cop0_codegen_fixture.cpp")
target_compile_features(cop0_fixture_generator PRIVATE cxx_std_20)
target_link_libraries(cop0_fixture_generator PRIVATE ps2_recomp_lib)
set(_cop0_generated "${CMAKE_BINARY_DIR}/cop0-generated.inc")
add_custom_command(OUTPUT "${_cop0_generated}"
    COMMAND $<TARGET_FILE:cop0_fixture_generator> "${_cop0_generated}"
    DEPENDS cop0_fixture_generator
    VERBATIM)
add_executable(cop0_generated_execution
    "${_cop0_test_root}/cop0_generated_execution.cpp" "${_cop0_generated}")
target_compile_features(cop0_generated_execution PRIVATE cxx_std_20)
target_include_directories(cop0_generated_execution PRIVATE
    "${CMAKE_SOURCE_DIR}/ps2xRuntime/include" "${CMAKE_BINARY_DIR}")
option(COP0_TEST_SANITIZE "Sanitize generated execution fixture" OFF)
if(COP0_TEST_SANITIZE AND NOT MSVC)
    target_compile_options(cop0_generated_execution PRIVATE
        -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(cop0_generated_execution PRIVATE -fsanitize=address,undefined)
endif()
enable_testing()
add_test(NAME cop0_exhaustive_generated_execution COMMAND cop0_generated_execution)
set_tests_properties(cop0_exhaustive_generated_execution PROPERTIES
    TIMEOUT 60 ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0")

add_executable(vif1_command_trace_test "${_cop0_test_root}/vif1_command_trace_test.cpp")
target_compile_features(vif1_command_trace_test PRIVATE cxx_std_20)
target_include_directories(vif1_command_trace_test PRIVATE "${CMAKE_SOURCE_DIR}/ps2xRuntime/include")
if(COP0_TEST_SANITIZE AND NOT MSVC)
    target_compile_options(vif1_command_trace_test PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(vif1_command_trace_test PRIVATE -fsanitize=address,undefined)
endif()
add_test(NAME vif1_command_trace_wraparound COMMAND vif1_command_trace_test)
set_tests_properties(vif1_command_trace_wraparound PROPERTIES TIMEOUT 60 ENVIRONMENT "ASAN_OPTIONS=detect_leaks=0")
