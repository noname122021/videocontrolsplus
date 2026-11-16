ARCHS = armv7
TARGET = iphone:clang:6.1:4.3

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = VideoControlsPlusPrefs
VideoControlsPlusPrefs_FILES = VideoControlsPlusListController.m
VideoControlsPlusPrefs_INSTALL_PATH = /Library/PreferenceBundles
VideoControlsPlusPrefs_FRAMEWORKS = UIKit CoreGraphics CoreFoundation
VideoControlsPlusPrefs_PRIVATE_FRAMEWORKS = Preferences
VideoControlsPlusPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
