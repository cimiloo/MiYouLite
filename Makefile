export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64
export DEBUG = 0
export FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = JijianContacts

JijianContacts_FILES = main.m AppDelegate.m MainViewController.m DeptViewController.m JJData.m JJToast.m
JijianContacts_FRAMEWORKS = UIKit Foundation
JijianContacts_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable

include $(THEOS_MAKE_PATH)/application.mk
