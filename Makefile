export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

# ── Tweak: 防撤回 + 密友隐藏 ──
TWEAK_NAME = MiYouLite
MiYouLite_FILES = Tweak.xm
MiYouLite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MiYouLite_FRAMEWORKS = UIKit Foundation
include $(THEOS_MAKE_PATH)/tweak.mk

# ── 设置面板作为独立子项目 (SUBPROJECT)，与 Tweak 完全隔离作用域 ──
SUBPROJECTS = prefs

after-install::
	install.exec "killall -9 WeChat"
