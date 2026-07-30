include $(THEOS)/makefiles/common.mk

# ── 设置面板子工程：标准 bundle.mk 构建真正的 NSBundle ──
# PSListController 的真实实现在设备端 Preferences 私有框架（roothide SDK 不含其 stub），
# 该 bundle 由 Preferences.app 加载，运行期符号必然存在；故链接器对未定义符号做动态查找。
BUNDLE_NAME = MiYouLitePrefs
MiYouLitePrefs_FILES = MiYouLitePrefs.m
MiYouLitePrefs_CFLAGS = -fobjc-arc -Wno-error
MiYouLitePrefs_FRAMEWORKS = UIKit Foundation
MiYouLitePrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
MiYouLitePrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
