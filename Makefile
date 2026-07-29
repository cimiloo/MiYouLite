# 【诊断实验】仅单 instance library，验证 roothide library.mk 能否正常链接含 PSListController 子类的 .m
export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = roothide

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = MiYouLitePrefs
MiYouLitePrefs_FILES = MiYouLitePrefs.m
MiYouLitePrefs_CFLAGS = -fobjc-arc
MiYouLitePrefs_FRAMEWORKS = UIKit Foundation
MiYouLitePrefs_INSTALL_PATH = /Library/PreferenceBundles/MiYouLitePrefs.bundle
MiYouLitePrefs_LIBRARY_EXTENSION = -
include $(THEOS_MAKE_PATH)/library.mk
