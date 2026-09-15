TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = LiveTouchEngine
LiveTouchEngine_FILES = LiveTouchEngine.m
LiveTouchEngine_FRAMEWORKS = UIKit AVFoundation
LiveTouchEngine_CFLAGS = -fobjc-arc
LiveTouchEngine_INSTALL_PATH = /usr/local/lib

include $(THEOS_MAKE_PATH)/library.mk
