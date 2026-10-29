TARGET := iphone:clang:6.1:4.3
ARCHS = armv7

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = VideoControlsPlus
VideoControlsPlus_FILES = Tweak.xm
VideoControlsPlus_FRAMEWORKS = UIKit CoreGraphics QuartzCore
VideoControlsPlus_LDFLAGS = -lsubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
