cmake_minimum_required(VERSION 3.4.1)

add_library(singbox-exec SHARED singbox_exec.c)

target_link_libraries(singbox-exec log dl)
