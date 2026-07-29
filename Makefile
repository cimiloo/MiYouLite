export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MiYouLite

MiYouLite_FILES = Tweak.xm
MiYouLite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MiYouLite_FRAMEWORKS = UIKit Foundation

BUNDLE_NAME = MiYouLitePrefs
MiYouLitePrefs_FILES = prefs/MiYouLitePrefsController.xm
MiYouLitePrefs_CFLAGS = -fobjc-arc
MiYouLitePrefs_FRAMEWORKS = UIKit Foundation
MiYouLitePrefs_PRIVATE_FRAMEWORKS = Preferences
MiYouLitePrefs_INSTALL_PATH = /Library/PreferenceBundles
MiYouLitePrefs_RESOURCE_DIRS = prefs/Resources

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

after-install::
	install.exec "killall -9 WeChat"