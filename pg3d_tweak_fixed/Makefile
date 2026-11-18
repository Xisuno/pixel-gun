THEOS_PACKAGE_SCHEME = rootless

TARGET  := iphone:clang:16.5:14.0
ARCHS   := arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := PG3DCheat

PG3DCheat_FILES := \
    Sources/PG3DCheat/Tweak.x \
    Sources/PG3DCheat/PG3DConfig.mm \
    Sources/PG3DCheat/ESPOverlayView.mm \
    Sources/PG3DCheat/AimHelper.xm

PG3DCheat_CFLAGS  := -fobjc-arc -I$(THEOS_PROJECT_DIR)/Sources/PG3DCheat
PG3DCheat_CCFLAGS := -fobjc-arc -std=c++17 -I$(THEOS_PROJECT_DIR)/Sources/PG3DCheat

PG3DCheat_FRAMEWORKS := UIKit CoreGraphics Foundation

# Bundle ID of Pixel Gun 3D — tweak only injects into this process
PG3DCheat_BUNDLE_ID := com.rilisoft.pixelgun3d

include $(THEOS)/makefiles/tweak.mk

# Theos package metadata
PACKAGE_VERSION = $(THEOS_PACKAGE_VERSION)

after-install::
	install.exec "killall -9 pixelgun3d || true"
