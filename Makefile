THEOS_PACKAGE_SCHEME = rootless

TARGET  := iphone:clang:16.5:14.0
# BUGFIX (mc1h): the installed game binary is arm64-only (confirmed via
# `lipo -info` on-device: "is architecture: arm64", no arm64e slice).
# An arm64e-only tweak dylib cannot be injected into an arm64-only process —
# dyld refuses the mismatched slice, and it fails completely silently: no
# crash, no log line, nothing. That's exactly why even the always-on UI
# marker never appeared despite the filter/bundle-id/permissions all being
# correct. Build for arm64 to match the actual target process.
ARCHS   := arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := PG3DCheat

PG3DCheat_FILES := \
    Sources/PG3DCheat/Tweak.x \
    Sources/PG3DCheat/PG3DConfig.mm \
    Sources/PG3DCheat/ESPOverlayView.mm \
    Sources/PG3DCheat/AimHelper.xm

PG3DCheat_CFLAGS  := -fobjc-arc -I$(THEOS_PROJECT_DIR)/Sources/PG3DCheat
PG3DCheat_CCFLAGS := -fobjc-arc -std=c++17 -I$(THEOS_PROJECT_DIR)/Sources/PG3DCheat
PG3DCheat_CFLAGS  += -Wno-error -Wno-unused-variable

PG3DCheat_FRAMEWORKS := UIKit CoreGraphics Foundation

PG3DCheat_LDFLAGS += -Wl,-undefined,dynamic_lookup

# Bundle ID of Pixel Gun 3D — tweak only injects into this process
PG3DCheat_BUNDLE_ID := zombiegun3d

include $(THEOS)/makefiles/tweak.mk

# Theos package metadata
PACKAGE_VERSION = $(THEOS_PACKAGE_VERSION)

after-install::
	install.exec "killall -9 pixelgun3d || true"
