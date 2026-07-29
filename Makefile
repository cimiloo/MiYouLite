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

# ── 设置面板 Bundle (密码保护) ──
BUNDLE_NAME = MiYouLitePrefs
MiYouLitePrefs_FILES = prefs/MiYouLitePrefsController.xm
MiYouLitePrefs_CFLAGS = -fobjc-arc
MiYouLitePrefs_FRAMEWORKS = UIKit Foundation
# 注意：PSListController 等符号运行期由 Preferences.app 动态提供，
# roothide SDK 无 Preferences.framework 可链接，故不写 PRIVATE_FRAMEWORKS（仅编译期用 <Preferences/Preferences.h> 头）。
MiYouLitePrefs_INSTALL_PATH = /Library/PreferenceBundles
MiYouLitePrefs_RESOURCE_DIRS = prefs/Resources
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 WeChat"
