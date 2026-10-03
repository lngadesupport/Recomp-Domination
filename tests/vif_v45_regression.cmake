include_guard(GLOBAL)
add_executable(vif_v45_color_test
    "${CMAKE_CURRENT_LIST_DIR}/vif_v45_color_test.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/test_function_table.cpp")
target_compile_features(vif_v45_color_test PRIVATE cxx_std_20)
target_link_libraries(vif_v45_color_test PRIVATE ps2_runtime)
if(MSVC)
    target_compile_options(vif_v45_color_test PRIVATE /arch:AVX2)
    target_link_options(vif_v45_color_test PRIVATE /STACK:8388608)
else()
    target_compile_options(vif_v45_color_test PRIVATE -mavx2)
endif()
enable_testing()
add_test(NAME vif_v45_all_colors COMMAND vif_v45_color_test)
set_tests_properties(vif_v45_all_colors PROPERTIES TIMEOUT 60)

add_executable(gs_sdk_clear_packet_test
    "${CMAKE_CURRENT_LIST_DIR}/gs_sdk_clear_packet_test.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/test_function_table.cpp")
target_compile_features(gs_sdk_clear_packet_test PRIVATE cxx_std_20)
target_link_libraries(gs_sdk_clear_packet_test PRIVATE ps2_runtime)
if(MSVC)
    target_compile_options(gs_sdk_clear_packet_test PRIVATE /arch:AVX2)
    target_link_options(gs_sdk_clear_packet_test PRIVATE /STACK:8388608)
else()
    target_compile_options(gs_sdk_clear_packet_test PRIVATE -mavx2)
endif()
add_test(NAME gs_sdk_clear_packet COMMAND gs_sdk_clear_packet_test)
set_tests_properties(gs_sdk_clear_packet PROPERTIES TIMEOUT 60)

add_executable(guest_missing_target_trace_test
    "${CMAKE_CURRENT_LIST_DIR}/guest_missing_target_trace_test.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/test_function_table.cpp")
target_compile_features(guest_missing_target_trace_test PRIVATE cxx_std_20)
target_link_libraries(guest_missing_target_trace_test PRIVATE ps2_runtime)
if(MSVC)
    target_compile_options(guest_missing_target_trace_test PRIVATE /arch:AVX2)
    target_link_options(guest_missing_target_trace_test PRIVATE /STACK:8388608)
else()
    target_compile_options(guest_missing_target_trace_test PRIVATE -mavx2)
endif()
foreach(mode IN ITEMS enabled disabled malformed)
    add_test(NAME guest_missing_target_${mode} COMMAND guest_missing_target_trace_test ${mode})
    if(mode STREQUAL "enabled")
        set_tests_properties(guest_missing_target_${mode} PROPERTIES ENVIRONMENT "PS2_TRACE_GUEST_MISSING_TARGETS=1")
    elseif(mode STREQUAL "disabled")
        set_tests_properties(guest_missing_target_${mode} PROPERTIES ENVIRONMENT "PS2_TRACE_GUEST_MISSING_TARGETS=0")
    else()
        set_tests_properties(guest_missing_target_${mode} PROPERTIES ENVIRONMENT "PS2_TRACE_GUEST_MISSING_TARGETS=garbage")
    endif()
    set_tests_properties(guest_missing_target_${mode} PROPERTIES TIMEOUT 60)
endforeach()

add_executable(guest_checkpoint_return_test
    "${CMAKE_CURRENT_LIST_DIR}/guest_checkpoint_return_test.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/test_function_table.cpp")
target_compile_features(guest_checkpoint_return_test PRIVATE cxx_std_20)
target_link_libraries(guest_checkpoint_return_test PRIVATE ps2_runtime)
if(MSVC)
    target_compile_options(guest_checkpoint_return_test PRIVATE /arch:AVX2)
    target_link_options(guest_checkpoint_return_test PRIVATE /STACK:8388608)
else()
    target_compile_options(guest_checkpoint_return_test PRIVATE -mavx2)
endif()
add_test(NAME guest_checkpoint_return COMMAND guest_checkpoint_return_test)
set_tests_properties(guest_checkpoint_return PROPERTIES TIMEOUT 60)

add_executable(gif_image2_test
    "${CMAKE_CURRENT_LIST_DIR}/gif_image2_test.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/test_function_table.cpp")
target_compile_features(gif_image2_test PRIVATE cxx_std_20)
target_link_libraries(gif_image2_test PRIVATE ps2_runtime)
if(MSVC)
    target_compile_options(gif_image2_test PRIVATE /arch:AVX2)
    target_link_options(gif_image2_test PRIVATE /STACK:8388608)
else()
    target_compile_options(gif_image2_test PRIVATE -mavx2)
endif()
add_test(NAME gif_image2 COMMAND gif_image2_test)
set_tests_properties(gif_image2 PROPERTIES TIMEOUT 60)

foreach(mode IN ITEMS enabled disabled malformed)
    add_test(NAME vu_xgkick_error_${mode} COMMAND gif_image2_test oversized)
    if(mode STREQUAL "enabled")
        set_tests_properties(vu_xgkick_error_${mode} PROPERTIES
            ENVIRONMENT "PS2_TRACE_VU_XGKICK_ERRORS=1"
            PASS_REGULAR_EXPRESSION "reason=tag-limit.*source_qw=0.*nloop=4096.*format=0.*nreg=0.*requested=1048592.*limit=65536")
    elseif(mode STREQUAL "disabled")
        set_tests_properties(vu_xgkick_error_${mode} PROPERTIES
            ENVIRONMENT "PS2_TRACE_VU_XGKICK_ERRORS=0"
            FAIL_REGULAR_EXPRESSION "vu:xgkick-error")
    else()
        set_tests_properties(vu_xgkick_error_${mode} PROPERTIES
            ENVIRONMENT "PS2_TRACE_VU_XGKICK_ERRORS=garbage"
            FAIL_REGULAR_EXPRESSION "vu:xgkick-error")
    endif()
    set_tests_properties(vu_xgkick_error_${mode} PROPERTIES TIMEOUT 60)
endforeach()

add_test(NAME vu_xgkick_history COMMAND gif_image2_test oversized)
set_tests_properties(vu_xgkick_history PROPERTIES TIMEOUT 60
    ENVIRONMENT "PS2_TRACE_VU_XGKICK_ERRORS=1;PS2_TRACE_VU_XGKICK_HISTORY=1;PS2_TRACE_VU_XGKICK_SOURCE_QW=0"
    PASS_REGULAR_EXPRESSION "vu:xgkick-step.*pc=0x0.*lower=0x800006fc")
add_test(NAME vu_xgkick_history_bad_source COMMAND gif_image2_test oversized)
set_tests_properties(vu_xgkick_history_bad_source PROPERTIES TIMEOUT 60
    ENVIRONMENT "PS2_TRACE_VU_XGKICK_ERRORS=1;PS2_TRACE_VU_XGKICK_HISTORY=1;PS2_TRACE_VU_XGKICK_SOURCE_QW=bad"
    FAIL_REGULAR_EXPRESSION "vu:xgkick-history|vu:xgkick-step|vu:xgkick-store")

add_executable(downhill_frame_state_test
    "${CMAKE_CURRENT_LIST_DIR}/downhill_frame_state_test.cpp"
    "${CMAKE_SOURCE_DIR}/ps2xTest/src/test_function_table.cpp")
target_compile_features(downhill_frame_state_test PRIVATE cxx_std_20)
target_include_directories(downhill_frame_state_test PRIVATE "${CMAKE_SOURCE_DIR}/ps2xRuntime/src/lib/Kernel")
target_link_libraries(downhill_frame_state_test PRIVATE ps2_runtime)
if(MSVC)
    target_compile_options(downhill_frame_state_test PRIVATE /arch:AVX2)
    target_link_options(downhill_frame_state_test PRIVATE /STACK:8388608)
else()
    target_compile_options(downhill_frame_state_test PRIVATE -mavx2)
endif()
add_test(NAME downhill_frame_state_passthrough COMMAND downhill_frame_state_test)
set_tests_properties(downhill_frame_state_passthrough PROPERTIES TIMEOUT 60)
