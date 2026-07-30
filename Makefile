export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

# ── Tweak: 防撤回 + 密友隐藏 ──
TWEAK_NAME = MiYouLite
MiYouLite_FILES = Tweak.xm
MiYouLite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
MiYouLite_FRAMEWORKS = UIKit Foundation
include $(THEOS_MAKE_PATH)/tweak.mk

# ── 设置面板子工程：标准 bundle.mk 构建真正的 NSBundle（preferences/ 目录）──
SUBPROJECTS = preferences
include $(THEOS_MAKE_PATH)/aggregate.mk

after-install::
	install.exec "killall -9 WeChat"
