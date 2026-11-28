THEOS_PACKAGE_SCHEME ?= roothide
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = SpringBoard Preferences
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = NextSummary
NextSummary_FILES = Tweak.m Shared.m
NextSummary_CFLAGS = -fobjc-arc
NextSummary_FRAMEWORKS = UIKit Foundation
NextSummary_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += Prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
