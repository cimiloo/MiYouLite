export TARGET = iphone:clang::14.0
export ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MiYouLite

MiYouLite_FILES = Tweak.xm
MiYouLite_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
MiYouLite_FRAMEWORKS = UIKit Foundation
MiYouLite_PRIVATE_FRAMEWORKS = 

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 WeChat"