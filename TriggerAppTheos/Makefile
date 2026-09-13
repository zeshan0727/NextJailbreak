ARCHS = arm64
TARGET = iphone:clang:latest:16.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = NextJailbreakTrigger
NextJailbreakTrigger_FILES = main.m
NextJailbreakTrigger_FRAMEWORKS = UIKit Foundation Security
NextJailbreakTrigger_CFLAGS = -fobjc-arc -include $(THEOS_PROJECT_DIR)/Compat.h
NextJailbreakTrigger_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
