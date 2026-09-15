TARGET := iphone:clang:16.5:15.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LiveTouch
LiveTouch_FILES = main.m LTAppDelegate.m LTRootViewController.m LTSpawnRoot.m LTRootHelperEmbedded.m
LiveTouch_FRAMEWORKS = UIKit AVFoundation UniformTypeIdentifiers
LiveTouch_CFLAGS = -fobjc-arc -Wno-error=deprecated-declarations
LiveTouch_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
