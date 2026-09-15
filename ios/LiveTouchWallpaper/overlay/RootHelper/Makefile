TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

TOOL_NAME = LiveTouchRootHelper
LiveTouchRootHelper_FILES = main.m
LiveTouchRootHelper_FRAMEWORKS = Foundation
LiveTouchRootHelper_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tool.mk
