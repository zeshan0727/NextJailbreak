ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:16.0
THEOS_PACKAGE_SCHEME ?= roothide
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = NotifyIslandPrefs
NotifyIslandPrefs_FILES = NISettingsController.m
NotifyIslandPrefs_FRAMEWORKS = Foundation UIKit
NotifyIslandPrefs_PRIVATE_FRAMEWORKS = Preferences
NotifyIslandPrefs_INSTALL_PATH = /Library/PreferenceBundles
NotifyIslandPrefs_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/bundle.mk
