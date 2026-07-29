include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = MiYouLitePrefs
MiYouLitePrefs_FILES = MiYouLitePrefs.m
MiYouLitePrefs_CFLAGS = -fobjc-arc
MiYouLitePrefs_FRAMEWORKS = UIKit Foundation
# 注意：PSListController 等符号运行期由 Preferences.app 动态提供，
# roothide SDK 无 Preferences.framework 可链接，故不写 PRIVATE_FRAMEWORKS（仅编译期用 <Preferences/Preferences.h> 头）。
MiYouLitePrefs_INSTALL_PATH = /Library/PreferenceBundles
MiYouLitePrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/bundle.mk
