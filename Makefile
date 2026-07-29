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

# ── 设置面板：用 library.mk 构建成动态库，再与 Layout 里的 Info.plist/Root.plist 组成 MiYouLitePrefs.bundle ──
# 说明：roothide-theos 的 bundle.mk 链接存在 object 收集 bug（链接时丢源文件 object），
# 故改用链接可靠的 library.mk（与 tweak.mk 同底层），手动组装 .bundle。
LIBRARY_NAME = MiYouLitePrefs
MiYouLitePrefs_FILES = prefs/MiYouLitePrefs.m
MiYouLitePrefs_CFLAGS = -fobjc-arc
MiYouLitePrefs_FRAMEWORKS = UIKit Foundation
MiYouLitePrefs_INSTALL_PATH = /Library/PreferenceBundles/MiYouLitePrefs.bundle
MiYouLitePrefs_LIBRARY_EXTENSION = -
include $(THEOS_MAKE_PATH)/library.mk

after-install::
	install.exec "killall -9 WeChat"
