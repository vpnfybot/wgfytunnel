LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE    := singbox-exec
LOCAL_SRC_FILES := singbox_exec.c
LOCAL_LDLIBS    := -llog
include $(BUILD_SHARED_LIBRARY)
