#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#pragma mark - 配置管理器（CFPreferences 标准域，与设置 app 共享）

static NSString *const kMiYouLiteDomain = @"com.miyou.lite";

@interface MiYouLiteManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, assign) BOOL antiRevokeEnabled;
@property (nonatomic, assign) BOOL hideModeEnabled;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSArray *hiddenFriends; // wxid 列表（单聊/群均按 wxid 隐藏）
@property (nonatomic, assign) BOOL isUnlocked;         // 搜索框密码验证通过后为 YES
- (BOOL)isHidden:(NSString *)usrName;
- (void)reload;
@end

@implementation MiYouLiteManager
+ (instancetype)sharedManager {
    static MiYouLiteManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MiYouLiteManager alloc] init];
        [instance reload];
    });
    return instance;
}
- (instancetype)init {
    self = [super init];
    if (self) { _isUnlocked = NO; }
    return self;
}
- (void)reload {
    CFStringRef domain = (__bridge CFStringRef)kMiYouLiteDomain;
    CFPropertyListRef v;
    v = CFPreferencesCopyValue(CFSTR("antiRevokeEnabled"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    _antiRevokeEnabled = (v && CFGetTypeID(v) == CFBooleanGetTypeID()) ? (BOOL)CFBooleanGetValue((CFBooleanRef)v) : NO;
    if (v) CFRelease(v);
    v = CFPreferencesCopyValue(CFSTR("hideModeEnabled"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    _hideModeEnabled = (v && CFGetTypeID(v) == CFBooleanGetTypeID()) ? (BOOL)CFBooleanGetValue((CFBooleanRef)v) : NO;
    if (v) CFRelease(v);
    v = CFPreferencesCopyValue(CFSTR("password"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    _password = (v && CFGetTypeID(v) == CFStringGetTypeID()) ? (__bridge_transfer NSString *)v : @"";
    if (v && CFGetTypeID(v) != CFStringGetTypeID()) CFRelease(v);
    // hiddenFriends 在设置 app 中以换行分隔的字符串存储，这里转为数组
    v = CFPreferencesCopyValue(CFSTR("hiddenFriends"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSString *raw = (v && CFGetTypeID(v) == CFStringGetTypeID()) ? (__bridge_transfer NSString *)v : @"";
    if (v && CFGetTypeID(v) != CFStringGetTypeID()) CFRelease(v);
    NSMutableArray *arr = [NSMutableArray array];
    for (NSString *line in [raw componentsSeparatedByString:@"\n"]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0) [arr addObject:t];
    }
    _hiddenFriends = arr;
}
- (BOOL)isHidden:(NSString *)usrName {
    if (!self.hideModeEnabled || self.isUnlocked) return NO;
    return [self.hiddenFriends containsObject:usrName ?: @""];
}
@end

// 监听设置变更后刷新会话列表
static void MiYouLiteForceReloadSessions(void) {
    Class cls = objc_getClass("MMNewSessionMgr");
    if (!cls) return;
    id mgr = [cls performSelector:@selector(getSessionMgr)] ?: nil;
    if (!mgr) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"MiYouLiteNeedReloadSession" object:nil];
        return;
    }
    if ([mgr respondsToSelector:@selector(rebuildMainSessions)]) {
        [mgr performSelector:@selector(rebuildMainSessions)];
    } else if ([mgr respondsToSelector:@selector(updateMainSessionList)]) {
        [mgr performSelector:@selector(updateMainSessionList)];
    }
}

#pragma mark - 防撤回（基于原 MiYou.dylib 真实符号 onRevokeMsg:）

%hook CMessageMgr
- (void)onRevokeMsg:(id)arg1 {
    if ([MiYouLiteManager sharedManager].antiRevokeEnabled) {
        NSLog(@"[MiYouLite] 拦截撤回: %@", arg1);
        return;
    }
    %orig;
}
%end

#pragma mark - 密友 - 过滤联系人（CContactMgr.getContact:/getAllContacts，字段 m_nsUsrName）

%hook CContactMgr
- (id)getContact:(id)arg1 {
    id contact = %orig;
    if (!contact) return nil;
    NSString *usrName = @"";
    @try { usrName = [contact valueForKey:@"m_nsUsrName"]; } @catch (NSException *e) {}
    if ([[MiYouLiteManager sharedManager] isHidden:usrName]) {
        return nil;
    }
    return contact;
}
- (id)getAllContacts {
    id contacts = %orig;
    MiYouLiteManager *mgr = [MiYouLiteManager sharedManager];
    if (!mgr.hideModeEnabled || mgr.isUnlocked) return contacts;
    if (![contacts isKindOfClass:[NSArray class]]) return contacts;
    NSMutableArray *filtered = [NSMutableArray array];
    for (id contact in contacts) {
        NSString *usrName = @"";
        @try { usrName = [contact valueForKey:@"m_nsUsrName"]; } @catch (NSException *e) {}
        if (![mgr isHidden:usrName]) {
            [filtered addObject:contact];
        }
    }
    return filtered;
}
%end

#pragma mark - 密友 - 过滤会话（MMNewSessionMgr.GetSessionCount/GetSessionAtIndex:，字段 m_nsUserName）
// 使用 MSHookMessageEx 手动 hook，以便拿到 original IMP，避免递归死循环。

typedef int (*OrigGetSessionCount)(id, SEL);
typedef id  (*OrigGetSessionAtIndex)(id, SEL, int);

static OrigGetSessionCount  g_origGetSessionCount = NULL;
static OrigGetSessionAtIndex g_origGetSessionAtIndex = NULL;

static int MiYouLite_GetSessionCount(id self, SEL _cmd) {
    int count = g_origGetSessionCount(self, _cmd);
    MiYouLiteManager *mgr = [MiYouLiteManager sharedManager];
    if (!mgr.hideModeEnabled || mgr.isUnlocked) return count;
    int hidden = 0;
    for (int i = 0; i < count; i++) {
        id session = g_origGetSessionAtIndex(self, @selector(GetSessionAtIndex:), i);
        if (!session) continue;
        NSString *name = @"";
        @try { name = [session valueForKey:@"m_nsUserName"]; } @catch (NSException *e) {}
        if ([mgr isHidden:name]) hidden++;
    }
    return MAX(0, count - hidden);
}

static id MiYouLite_GetSessionAtIndex(id self, SEL _cmd, int arg1) {
    MiYouLiteManager *mgr = [MiYouLiteManager sharedManager];
    if (!mgr.hideModeEnabled || mgr.isUnlocked) {
        return g_origGetSessionAtIndex(self, _cmd, arg1);
    }
    int count = g_origGetSessionCount(self, @selector(GetSessionCount));
    int skipped = 0;
    for (int i = 0; i < count; i++) {
        id session = g_origGetSessionAtIndex(self, @selector(GetSessionAtIndex:), i);
        if (!session) continue;
        NSString *name = @"";
        @try { name = [session valueForKey:@"m_nsUserName"]; } @catch (NSException *e) {}
        if ([mgr isHidden:name]) { skipped++; continue; }
        if (skipped == arg1) return session;
        skipped++;
    }
    return nil;
}

#pragma mark - 密友 - 搜索框密码解锁（UISearchBar.textField EditingChanged）

%hook UISearchBar
- (void)layoutSubviews {
    %orig;
    UITextField *tf = nil;
    if (@available(iOS 13.0, *)) {
        tf = self.searchTextField;
    } else {
        @try { tf = [self valueForKey:@"_searchField"]; } @catch (NSException *e) {}
    }
    if (tf) {
        [tf removeTarget:self action:@selector(miYouLite_searchTextChanged:) forControlEvents:UIControlEventEditingChanged];
        [tf addTarget:self action:@selector(miYouLite_searchTextChanged:) forControlEvents:UIControlEventEditingChanged];
    }
}
- (void)dealloc {
    UITextField *tf = nil;
    if (@available(iOS 13.0, *)) {
        tf = self.searchTextField;
    } else {
        @try { tf = [self valueForKey:@"_searchField"]; } @catch (NSException *e) {}
    }
    [tf removeTarget:self action:@selector(miYouLite_searchTextChanged:) forControlEvents:UIControlEventEditingChanged];
    %orig;
}
%new
- (void)miYouLite_searchTextChanged:(UITextField *)textField {
    MiYouLiteManager *mgr = [MiYouLiteManager sharedManager];
    if (mgr.hideModeEnabled && mgr.password.length > 0) {
        if ([textField.text isEqualToString:mgr.password]) {
            mgr.isUnlocked = YES;
            MiYouLiteForceReloadSessions();
            NSLog(@"[MiYouLite] 密码匹配，已解锁密友");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                mgr.isUnlocked = NO;
                MiYouLiteForceReloadSessions();
            });
        }
    }
}
%end

#pragma mark - 构造函数：安装 MMNewSessionMgr 手动 hook + 设置变更监听

static void MiYouLiteSettingsChanged(CFNotificationCenterRef center,
                                     void *observer,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    [[MiYouLiteManager sharedManager] reload];
    MiYouLiteForceReloadSessions();
}

%ctor {
    NSLog(@"[MiYouLite] 插件已加载 - 版本 1.2.2 roothide (微信 8.0.75)");
    Class sessionMgrClass = objc_getClass("MMNewSessionMgr");
    if (sessionMgrClass) {
        Method mCount = class_getInstanceMethod(sessionMgrClass, @selector(GetSessionCount));
        Method mIndex = class_getInstanceMethod(sessionMgrClass, @selector(GetSessionAtIndex:));
        if (mCount) {
            MSHookMessageEx(sessionMgrClass, @selector(GetSessionCount),
                            (IMP)MiYouLite_GetSessionCount, (IMP *)&g_origGetSessionCount);
        }
        if (mIndex) {
            MSHookMessageEx(sessionMgrClass, @selector(GetSessionAtIndex:),
                            (IMP)MiYouLite_GetSessionAtIndex, (IMP *)&g_origGetSessionAtIndex);
        }
    }
    // 设置 app 修改后热重载
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    MiYouLiteSettingsChanged,
                                    CFSTR("com.miyou.lite/settings-changed"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
}

#pragma mark - 为 roothide PreferenceLoader 的 isController 预加载设置 bundle
// 根因：PL 在 Preferences.app 启动扫描入口 plist 时就 NSClassFromString(detail=类名)，
// 而该 bundle 本是点击设置项时才 lazyLoad 的，导致扫描时类尚未注册 → 类名解析为 nil →
// PL 回退 PLCustomListController（其 bundle 方法硬返回 PL 目录，找不到 Root.plist → 空白）。
// 这里在 Preferences 进程启动早期手动 load 该 bundle，使类名在 PL 扫描时可被解析。
#include <stdio.h>
__attribute__((constructor))
static void MiYouLitePrefsPreload(void) {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (!bid || ![bid isEqualToString:@"com.apple.Preferences"]) return;

        NSArray *cands = @[
            @"/var/jb/Library/PreferenceBundles/MiYouLitePrefs.bundle",
            @"/Library/PreferenceBundles/MiYouLitePrefs.bundle"
        ];
        for (NSString *p in cands) {
            NSBundle *b = [NSBundle bundleWithPath:p];
            if (!b) continue;
            NSError *e = nil;
            BOOL ok = [b loadAndReturnError:&e];
            BOOL clsOK = (NSClassFromString(@"MiYouLitePrefsController") != nil);
            NSLog(@"[MiYouLite] Preferences 预加载设置bundle path=%@ loaded=%d classResolved=%d err=%@",
                  p, ok, clsOK, e);
            FILE *lf = fopen("/var/jb/tmp/miyoulite_prefs.log", "a");
            if (lf) {
                fprintf(lf, "[MiYouLite] preload path=%s loaded=%d classResolved=%d err=%s\n",
                        p.UTF8String, ok, clsOK, [[e localizedDescription] UTF8String] ?: "");
                fclose(lf);
            }
            if (ok) break;
        }
    }
}
