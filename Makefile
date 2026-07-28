export TARGET = iphone:clang:16.5:14.0
export ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MiYouLite

MiYouLite_FILES = Tweak.xm
MiYouLite_CFLAGS = -fobjc-arc
MiYouLite_FRAMEWORKS = UIKit Foundation
MiYouLite_PRIVATE_FRAMEWORKS = 

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 WeChat"