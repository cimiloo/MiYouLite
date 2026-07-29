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

export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

after-install::
	install.exec "killall -9 WeChat"