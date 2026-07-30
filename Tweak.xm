#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <stdio.h>
#import <pthread.h>
#import <unistd.h>
#import <errno.h>

#pragma mark - 诊断日志（多候选路径，自动建目录；同时打到 syslog 便于跨沙盒验证）

// roothide 下各进程（系统 App / 沙盒 App）对 /tmp 的可见性不一，
// 故尝试多个候选目录，选第一个可写者；并把「最终落盘路径」打到 syslog，
// 方便用户在真机上确认日志到底写到了哪里（尤其微信这种沙盒进程）。
static NSArray *MYLCandidateLogDirs(void) {
    NSMutableArray *a = [NSMutableArray arrayWithArray:@[ @"/tmp", @"/var/mobile/Library/Preferences", @"/var/tmp" ]];
    NSString *appBase = @"/var/containers/Bundle/Application";
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:appBase]) {
        for (NSString *s in [fm contentsOfDirectoryAtPath:appBase error:nil] ?: @[]) {
            if ([s hasPrefix:@".jbroot"]) {
                // 真实 jbroot（roothide 无 /var/jb）：优先写这里，Settings 与微信都能读到
                [a insertObject:[appBase stringByAppendingPathComponent:
                    [s stringByAppendingPathComponent:@"Library/Preferences"]] atIndex:0];
                break;
            }
        }
    }
    // 进程自身沙盒 tmp（沙盒 App 必定可写，作为最后兜底）
    NSString *homeTmp = NSTemporaryDirectory();
    if (homeTmp.length) [a addObject:homeTmp];
    return a;
}

static NSString *MYLLogFile(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *d in MYLCandidateLogDirs()) {
        if ([fm fileExistsAtPath:d] || [fm createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil]) {
            return [d stringByAppendingPathComponent:@"miyoulite_prefs.log"];
        }
    }
    return @"/tmp/miyoulite_prefs.log";
}

#define MYLLog(...) do { \
    NSString *__msg = [NSString stringWithFormat:__VA_ARGS__]; \
    NSLog(@"[MiYouLite] %@", __msg); \
    NSString *__p = MYLLogFile(); \
    FILE *__lf = fopen([__p UTF8String], "a"); \
    if (__lf) { fprintf(__lf, "[MiYouLite] %s\n", [__msg UTF8String]); fclose(__lf); } \
} while(0)

#pragma mark - 微信侧诊断日志（写进微信自己的容器 Documents，Filza 可读，无需 log stream）
// ★ 关键：微信是沙盒 App，写不了 /tmp 与 /var/mobile/Library/Preferences（fopen 静默失败），
//   所以之前的文件日志里永远看不到微信条目。微信自身容器 Documents 目录必定可写，
//   Filza 导航到「微信 → Library → ... 或 Documents」即可读取，彻底摆脱 log stream。
static NSString *MYLWeChatLogPath(void) {
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *dir = docs.firstObject;
    if (!dir) dir = NSTemporaryDirectory();
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"miyoulite_wechat.log"];
}
static void MYLWeChatLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[MiYouLite][WeChat] %@", msg);
    NSString *p = MYLWeChatLogPath();
    FILE *lf = fopen([p UTF8String], "a");
    if (lf) { fprintf(lf, "[MiYouLite][WeChat] %s\n", [msg UTF8String]); fclose(lf); }
}

// 枚举某个类的实例方法名，便于确认微信 8.0.75 里 hook 目标符号是否改名
static NSArray *MYLMethodsOfClass(NSString *clsName) {
    Class c = objc_getClass(clsName.UTF8String);
    if (!c) return @[@"CLASS_NOT_FOUND"];
    unsigned int count = 0;
    Method *methods = class_copyMethodList(c, &count);
    NSMutableArray *arr = [NSMutableArray array];
    for (unsigned i = 0; i < count; i++) {
        [arr addObject:NSStringFromSelector(method_getName(methods[i]))];
    }
    free(methods);
    return arr;
}
static NSString *MYLFilterMethods(NSArray *methods, NSArray *keywords) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *m in methods) {
        for (NSString *k in keywords) {
            if ([m rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [out addObject:m]; break;
            }
        }
    }
    return [out componentsJoinedByString:@", "];
}

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

// ── 跨进程共享配置 ──
// ★ v1.2.12 修复（roothide 跨进程隔离根因，最终方案）：
//   /rootfs 在微信(沙盒 App)进程里访问不到（sandbox 屏蔽，诊断已证实 rootfsExists=0）；
//   /var/mobile/Library/Preferences 是按 App 虚拟化的本地副本（官方 symlink 列表不含它）→ 不共享。
//   roothide 官方确认「/var/mobile/Containers 在 jbroot 视图里 symlink 到真实 rootfs」，故
//   微信容器 Documents 目录在设置 App 与微信两侧经该 symlink 指向同一真实物理文件。
//   方案：微信读「自己容器 Documents/com.miyou.lite.plist」(100% 可达、固定)；
//         设置面板用 LSApplicationProxy 找到微信容器真实路径写入同一文件 → 跨进程共享成立。
static NSArray *MYLConfigCandidateDirs(void) {
    NSMutableArray *a = [NSMutableArray array];
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.firstObject) [a addObject:docs.firstObject]; // 微信容器 Documents（主，双方算出的真实路径一致）
    [a addObject:@"/var/mobile"];                          // 顶层备选（官方 symlink 列表不含 → 可能共享）
    [a addObject:@"/var/mobile/Library/Preferences"];      // 虚拟化兜底
    return a;
}
// 微信侧读取：遍历候选，返回第一个已存在的 com.miyou.lite.plist；都不存在时默认主路径
static NSString *MYLSharedConfigFile(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *d in MYLConfigCandidateDirs()) {
        NSString *p = [d stringByAppendingPathComponent:@"com.miyou.lite.plist"];
        if ([fm fileExistsAtPath:p]) return p;
    }
    NSString *d0 = MYLConfigCandidateDirs().firstObject;
    return [d0 stringByAppendingPathComponent:@"com.miyou.lite.plist"];
}

static NSDictionary *MiYouLiteReadSharedConfig(void) {
    NSString *p = MYLSharedConfigFile();
    if (!p) return nil;
    return [NSDictionary dictionaryWithContentsOfFile:p];
}

// 注：MiYouLiteWriteSharedConfig 仅由设置面板（MiYouLitePrefs.m）调用，
// Tweak 进程本身只读取共享配置，故此处不重复定义，避免「未使用函数」被新版 clang 当 error。

#pragma mark - 配置管理器

static NSString *const kMiYouLiteDomain = @"com.miyou.lite";

@interface MiYouLiteManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, assign) BOOL antiRevokeEnabled;
@property (nonatomic, assign) BOOL hideModeEnabled;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSArray *hiddenFriends;
@property (nonatomic, assign) BOOL isUnlocked;
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
    NSDictionary *sc = MiYouLiteReadSharedConfig();
    CFStringRef domain = (__bridge CFStringRef)kMiYouLiteDomain;
    CFPropertyListRef v;

    // antiRevokeEnabled：优先共享文件，回退 CFPreferences
    if (sc && sc[@"antiRevokeEnabled"] != nil) {
        _antiRevokeEnabled = [sc[@"antiRevokeEnabled"] boolValue];
    } else {
        v = CFPreferencesCopyValue(CFSTR("antiRevokeEnabled"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        _antiRevokeEnabled = (v && CFGetTypeID(v) == CFBooleanGetTypeID()) ? (BOOL)CFBooleanGetValue((CFBooleanRef)v) : NO;
        if (v) CFRelease(v);
    }
    // hideModeEnabled
    if (sc && sc[@"hideModeEnabled"] != nil) {
        _hideModeEnabled = [sc[@"hideModeEnabled"] boolValue];
    } else {
        v = CFPreferencesCopyValue(CFSTR("hideModeEnabled"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        _hideModeEnabled = (v && CFGetTypeID(v) == CFBooleanGetTypeID()) ? (BOOL)CFBooleanGetValue((CFBooleanRef)v) : NO;
        if (v) CFRelease(v);
    }
    // password
    if (sc && sc[@"password"] != nil) {
        _password = [sc[@"password"] copy] ?: @"";
    } else {
        v = CFPreferencesCopyValue(CFSTR("password"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        _password = (v && CFGetTypeID(v) == CFStringGetTypeID()) ? (__bridge_transfer NSString *)v : @"";
        if (v && CFGetTypeID(v) != CFStringGetTypeID()) CFRelease(v);
    }
    // hiddenFriends（设置 app 中以换行分隔的字符串存储）
    NSString *raw = nil;
    if (sc && sc[@"hiddenFriends"] != nil) {
        raw = [sc[@"hiddenFriends"] isKindOfClass:[NSString class]] ? sc[@"hiddenFriends"] : [sc[@"hiddenFriends"] description];
    } else {
        v = CFPreferencesCopyValue(CFSTR("hiddenFriends"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        raw = (v && CFGetTypeID(v) == CFStringGetTypeID()) ? (__bridge_transfer NSString *)v : @"";
        if (v && CFGetTypeID(v) != CFStringGetTypeID()) CFRelease(v);
    }
    NSMutableArray *arr = [NSMutableArray array];
    for (NSString *line in [raw componentsSeparatedByString:@"\n"]) {
        NSString *t = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (t.length > 0) [arr addObject:t];
    }
    _hiddenFriends = arr;
    MYLLog(@"reload: antiRevoke=%d hide=%d friends=%lu pwd=%lu src=%@",
           _antiRevokeEnabled, _hideModeEnabled, (unsigned long)_hiddenFriends.count,
           (unsigned long)_password.length, sc ? @"shared-file" : @"CFPreferences");
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

#pragma mark - 防撤回（微信 8.0.75 真实符号：RevokeMsg:MsgWrap:Counter: / :revokeTicket:viewController:）
// ★ 修复「自己撤回就闪退」：原 %hook + %orig 在原始实现内部 self-dispatch 同一 selector 时
//   会无限递归 → 栈溢出崩溃。现改 MSHookMessageEx 拿原始 IMP，并在调用原始实现期间用
//   method_setImplementation 临时把该 selector 恢复为原始实现，使原始内部的 self-dispatch
//   也走原始（不再进 hook），递归自然终止。pthread_mutex 保护 swap+call 区间，避免并发错乱。

typedef void (*OrigRevoke3)(id, SEL, void*, void*, void*);
typedef void (*OrigRevoke5)(id, SEL, void*, void*, void*, void*, void*);

static OrigRevoke3 g_origRevoke3 = NULL;
static OrigRevoke5 g_origRevoke5 = NULL;
static int g_revokeRetry = 0;
static pthread_mutex_t g_revokeMutex = PTHREAD_MUTEX_INITIALIZER;

// 临时恢复 selector 为原始实现后调用（避免递归），调用完再换回 hook
static void MiYouLiteCallOrigRevoke(id self, SEL _cmd, IMP origImp, int argc, void *a1, void *a2, void *a3, void *a4, void *a5) {
    Class cls = object_getClass(self);
    Method m = class_getInstanceMethod(cls, _cmd);
    if (!m || !origImp) return;
    IMP hooked = method_getImplementation(m);
    method_setImplementation(m, origImp);   // 临时恢复原始，原始内部 self-dispatch 同 selector 也走原始
    if (argc == 3) ((OrigRevoke3)origImp)(self, _cmd, a1, a2, a3);
    else           ((OrigRevoke5)origImp)(self, _cmd, a1, a2, a3, a4, a5);
    method_setImplementation(m, hooked);    // 恢复 hook
}

static void MiYouLite_Revoke3(id self, SEL _cmd, id arg1, id arg2, id arg3) {
    MiYouLiteManager *mgr = [MiYouLiteManager sharedManager];
    if (mgr.antiRevokeEnabled) {
        MYLWeChatLog(@"*** 防撤回触发(RevokeMsg:MsgWrap:Counter:) *** msg=%@ wrap=%@", arg1, arg2);
        return; // 拦截：不调原始，撤回不生效
    }
    MYLWeChatLog(@"(防撤回未开启) 收到撤回请求 RevokeMsg:MsgWrap:Counter:");
    pthread_mutex_lock(&g_revokeMutex);
    MiYouLiteCallOrigRevoke(self, _cmd, (IMP)g_origRevoke3, 3, (__bridge void*)arg1, (__bridge void*)arg2, (__bridge void*)arg3, NULL, NULL);
    pthread_mutex_unlock(&g_revokeMutex);
}
static void MiYouLite_Revoke5(id self, SEL _cmd, id arg1, id arg2, id arg3, id arg4, id arg5) {
    MiYouLiteManager *mgr = [MiYouLiteManager sharedManager];
    if (mgr.antiRevokeEnabled) {
        MYLWeChatLog(@"*** 防撤回触发(RevokeMsg:...:revokeTicket:viewController:) ***");
        return;
    }
    MYLWeChatLog(@"(防撤回未开启) 收到撤回请求 RevokeMsg:...:revokeTicket:viewController:");
    pthread_mutex_lock(&g_revokeMutex);
    MiYouLiteCallOrigRevoke(self, _cmd, (IMP)g_origRevoke5, 5, (__bridge void*)arg1, (__bridge void*)arg2, (__bridge void*)arg3, (__bridge void*)arg4, (__bridge void*)arg5);
    pthread_mutex_unlock(&g_revokeMutex);
}

static void MiYouLiteHookRevoke(void) {
    Class cls = objc_getClass("CMessageMgr");
    if (!cls) {
        if (g_revokeRetry++ < 60) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ MiYouLiteHookRevoke(); });
        } else {
            MYLLog(@"CMessageMgr 始终未加载，防撤回禁用");
            MYLWeChatLog(@"CMessageMgr 始终未加载（30s 内），防撤回 hook 未安装");
        }
        return;
    }
    if (g_origRevoke3) return; // 已安装
    Method m3 = class_getInstanceMethod(cls, @selector(RevokeMsg:MsgWrap:Counter:));
    Method m5 = class_getInstanceMethod(cls, @selector(RevokeMsg:MsgWrap:Counter:revokeTicket:viewController:));
    if (m3) MSHookMessageEx(cls, @selector(RevokeMsg:MsgWrap:Counter:),
                            (IMP)MiYouLite_Revoke3, (IMP *)&g_origRevoke3);
    if (m5) MSHookMessageEx(cls, @selector(RevokeMsg:MsgWrap:Counter:revokeTicket:viewController:),
                            (IMP)MiYouLite_Revoke5, (IMP *)&g_origRevoke5);
    MYLLog(@"Revoke hooks 已安装 (3=%d 5=%d)", m3 != nil, m5 != nil);
    MYLWeChatLog(@"Revoke hooks 已安装 (3=%d 5=%d)", m3 != nil, m5 != nil);
}

#pragma mark - 密友 - 过滤联系人（CContactMgr.getContact:/getAllContacts，字段 m_nsUsrName）

%hook CContactMgr
static BOOL g_getContactHit = NO;
static BOOL g_getAllHit = NO;
- (id)getContact:(id)arg1 {
    id contact = %orig;
    if (!g_getContactHit) {
        g_getContactHit = YES;
        MYLWeChatLog(@"[hook] CContactMgr getContact: 已触发（hide=%d）",
            [MiYouLiteManager sharedManager].hideModeEnabled);
    }
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
    if (!g_getAllHit) {
        g_getAllHit = YES;
        MYLWeChatLog(@"[hook] CContactMgr getAllContacts 已触发（hide=%d, 返回%lu项）",
            mgr.hideModeEnabled, (unsigned long)([contacts isKindOfClass:[NSArray class]] ? [contacts count] : 0));
    }
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
// ★ 修复：原先在 %ctor 里急切安装，但当时 MMNewSessionMgr 类尚未加载 → 永远装不上。
//   现改为「延迟重试安装」，直到该类可用为止（与 PLCustomListController 同思路）。

typedef int (*OrigGetSessionCount)(id, SEL);
typedef id  (*OrigGetSessionAtIndex)(id, SEL, int);

static OrigGetSessionCount  g_origGetSessionCount = NULL;
static OrigGetSessionAtIndex g_origGetSessionAtIndex = NULL;
static int g_sessionRetry = 0;

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

static void MiYouLiteHookSessionMgr(void) {
    Class cls = objc_getClass("MMNewSessionMgr");
    if (!cls) {
        if (g_sessionRetry++ < 60) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ MiYouLiteHookSessionMgr(); });
        } else {
            MYLLog(@"MMNewSessionMgr 始终未加载，会话隐藏禁用");
            MYLWeChatLog(@"MMNewSessionMgr 始终未加载（30s 内），会话 hook 未安装 —— 密友隐藏的会话列表部分失效");
        }
        return;
    }
    if (g_origGetSessionCount) return; // 已安装
    Method mCount = class_getInstanceMethod(cls, @selector(GetSessionCount));
    Method mIndex = class_getInstanceMethod(cls, @selector(GetSessionAtIndex:));
    if (mCount) MSHookMessageEx(cls, @selector(GetSessionCount),
                                (IMP)MiYouLite_GetSessionCount, (IMP *)&g_origGetSessionCount);
    if (mIndex) MSHookMessageEx(cls, @selector(GetSessionAtIndex:),
                                (IMP)MiYouLite_GetSessionAtIndex, (IMP *)&g_origGetSessionAtIndex);
    MYLLog(@"MMNewSessionMgr hooks 已安装 (count=%d index=%d)", mCount != nil, mIndex != nil);
    MYLWeChatLog(@"MMNewSessionMgr hooks 已安装 (count=%d index=%d)", mCount != nil, mIndex != nil);
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
            MYLLog(@"密码匹配，已解锁密友");
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                mgr.isUnlocked = NO;
                MiYouLiteForceReloadSessions();
            });
        }
    }
}
%end

#pragma mark - 设置变更通知（由设置 App 发出，微信收到后热重载 + 刷新会话）

static void MiYouLiteSettingsChanged(CFNotificationCenterRef center,
                                     void *observer,
                                     CFStringRef name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    [[MiYouLiteManager sharedManager] reload];
    MiYouLiteForceReloadSessions();
}

// 前向声明：MiYouLiteHookPL 定义在本文件靠后位置（PL 回退 hook），
// 但 %ctor 在上方已调用它。新版 clang（Xcode runner 升级后）把
// 「调用未声明函数（隐式函数声明）」当硬错误，故必须显式声明。
static void MiYouLiteHookPL(void);

%ctor {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
    MYLLog(@"tweak loaded, version=1.2.12, process=%@, log=%@", bid ?: @"(unknown)", MYLLogFile());

    // 诊断：微信侧报告关键类/方法是否存在 —— 用于确认 hook 目标符号是否过时（微信 8.0.75）
    if ([bid isEqualToString:@"com.tencent.xin"] || [bid isEqualToString:@"WeChat"]) {
        Class cm = objc_getClass("CMessageMgr");
        Class ccm = objc_getClass("CContactMgr");
        Class nsm = objc_getClass("MMNewSessionMgr");
        MYLLog(@"WeChat diag: CMessageMgr=%d onRevokeMsg=%d | CContactMgr=%d getContact=%d getAllContacts=%d | MMNewSessionMgr=%d GetSessionCount=%d GetSessionAtIndex=%d",
            !!cm, cm && !!class_getInstanceMethod(cm, @selector(onRevokeMsg:)),
            !!ccm, ccm && !!class_getInstanceMethod(ccm, @selector(getContact:)),
            ccm && !!class_getInstanceMethod(ccm, @selector(getAllContacts)),
            !!nsm, nsm && !!class_getInstanceMethod(nsm, @selector(GetSessionCount)),
            nsm && !!class_getInstanceMethod(nsm, @selector(GetSessionAtIndex:)));

        // 把诊断详情写到「微信自己的容器」，Filza 可读（无需 log stream）
        NSString *scPath = MYLSharedConfigFile();
        NSDictionary *sc = MiYouLiteReadSharedConfig();
        MYLWeChatLog(@"==== MiYouLite 微信诊断 (version=1.2.12) ====");
        MYLWeChatLog(@"bundleID=%@ docLog=%@ configFile=%@", bid, MYLWeChatLogPath(), scPath);
        // ★ 用 POSIX access 验证 /rootfs 在微信里到底能否访问（fileExistsAtPath 可能被 sandbox 误导）
        if (access("/rootfs/var/mobile/Library/Preferences", R_OK|W_OK) == 0)
            MYLWeChatLog(@"rootfs_access=RW_OK");
        else
            MYLWeChatLog(@"rootfs_access=fail errno=%d (微信沙盒访问不到 /rootfs，已改用自身容器)", errno);
        // ★ 关键：报告各候选路径 com.miyou.lite.plist 是否存在，确认共享文件是否被设置面板写入
        for (NSString *d in MYLConfigCandidateDirs()) {
            NSString *p = [d stringByAppendingPathComponent:@"com.miyou.lite.plist"];
            MYLWeChatLog(@"candidate[%@] exists=%d", p,
                (int)[[NSFileManager defaultManager] fileExistsAtPath:p]);
        }
        MYLWeChatLog(@"sharedConfigFile(resolved)=%@", scPath);
        MYLWeChatLog(@"sharedConfigFileExists=%d parsed=%@",
                     (int)[[NSFileManager defaultManager] fileExistsAtPath:scPath], sc ?: @"nil");
        if (sc) {
            MYLWeChatLog(@"sharedConfig: anti=%@ hide=%@ pwd.len=%lu friends.len=%lu",
                sc[@"antiRevokeEnabled"], sc[@"hideModeEnabled"],
                (unsigned long)[(sc[@"password"] ?: @"") length],
                (unsigned long)[(sc[@"hiddenFriends"] ?: @"") length]);
        }
        MiYouLiteManager *m = [MiYouLiteManager sharedManager];
        MYLWeChatLog(@"mgr.reload -> anti=%d hide=%d friends=%lu pwd.len=%lu",
            m.antiRevokeEnabled, m.hideModeEnabled,
            (unsigned long)m.hiddenFriends.count, (unsigned long)m.password.length);
        // 关键类存在性
        MYLWeChatLog(@"CLASS CMessageMgr=%d CContactMgr=%d MMNewSessionMgr=%d",
            !!cm, !!ccm, !!nsm);
        // 直接 dump 含关键词的方法名，确认 8.0.75 里符号是否改名
        MYLWeChatLog(@"CMessageMgr *Revoke*: %@",
            MYLFilterMethods(MYLMethodsOfClass(@"CMessageMgr"), @[@"Revoke", @"revoke"]));
        MYLWeChatLog(@"CMessageMgr *DelMsg/AddMsg*: %@",
            MYLFilterMethods(MYLMethodsOfClass(@"CMessageMgr"), @[@"DelMsg", @"AddMsg", @"DeleteMsg"]));
        MYLWeChatLog(@"MMNewSessionMgr *Session*: %@",
            MYLFilterMethods(MYLMethodsOfClass(@"MMNewSessionMgr"), @[@"Session", @"ession"]));
        NSArray *nsmAll = MYLMethodsOfClass(@"MMNewSessionMgr");
        if (nsmAll.count > 40) nsmAll = [nsmAll subarrayWithRange:NSMakeRange(0, 40)];
        MYLWeChatLog(@"MMNewSessionMgr all-methods(count<=40): %@",
            [nsmAll componentsJoinedByString:@", "]);
        MYLWeChatLog(@"CContactMgr *ontact*: %@",
            MYLFilterMethods(MYLMethodsOfClass(@"CContactMgr"), @[@"ontact", @"Contact"]));
    }

    MiYouLiteHookSessionMgr(); // 延迟重试安装会话 hook
    MiYouLiteHookRevoke();     // 延迟重试安装防撤回 hook（MSHookMessageEx，防递归崩溃）
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    MiYouLiteSettingsChanged,
                                    CFSTR("com.miyou.lite/settings-changed"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorCoalesce);
    MiYouLiteHookPL();
}

#pragma mark - 为 roothide PreferenceLoader 的 isController 预加载设置 bundle
// 根因：PL 在 Preferences.app 启动扫描入口 plist 时解析 detail=类名。
// 该 bundle 本是点击设置项时才 lazyLoad，扫描时类可能尚未注册 → 类名解析为 nil →
// PL 回退 PLCustomListController（其 bundle 返回 PL 目录，找不到 Root.plist → 空白）。
// 这里在 Preferences 进程启动早期手动 load 该 bundle，使类名在 PL 扫描时可被解析。

static void MiYouLiteTryPreload(void) {
    NSMutableArray *cands = [NSMutableArray arrayWithArray:@[
        @"/Library/PreferenceBundles/MiYouLitePrefs.bundle"
    ]];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *appBase = @"/var/containers/Bundle/Application";
    if ([fm fileExistsAtPath:appBase]) {
        for (NSString *s in [fm contentsOfDirectoryAtPath:appBase error:nil] ?: @[]) {
            if ([s hasPrefix:@".jbroot"]) {
                [cands addObject:[appBase stringByAppendingPathComponent:
                    [s stringByAppendingPathComponent:@"Library/PreferenceBundles/MiYouLitePrefs.bundle"]]];
            }
        }
    }
    for (NSString *p in cands) {
        NSBundle *b = [NSBundle bundleWithPath:p];
        if (!b) continue;
        if ([b isLoaded]) { MYLLog(@"preload already loaded: %@", p); return; }
        NSError *e = nil;
        BOOL ok = [b loadAndReturnError:&e];
        BOOL clsOK = (NSClassFromString(@"MiYouLitePrefsController") != nil);
        MYLLog(@"preload path=%@ loaded=%d classResolved=%d err=%@",
               p, ok, clsOK, e ? [e localizedDescription] : @"none");
        if (ok) return;
    }
    MYLLog(@"preload: bundle not preloaded (will lazy-load on tap; non-fatal)");
}

__attribute__((constructor))
static void MiYouLitePrefsPreload(void) {
    @autoreleasepool {
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier];
        if (!bid || ![bid isEqualToString:@"com.apple.Preferences"]) return;
        MiYouLiteTryPreload();
    }
}

#pragma mark - 确定性保险：hook roothide PL 的 PLCustomListController.bundle
// 当 detail 类名未能在扫描时解析，PL 会用 PLCustomListController 渲染我们的条目，
// 而它的 bundle 返回 PL 自身目录（找不到 Root.plist → 空白）。
// 这里 hook 其 bundle 方法：若 specifier 的 PSLazilyLoadedBundleKey 指向 MiYouLitePrefs，
// 则返回我们正确的 bundle。MSHookMessageEx 在类可用前会反复重试，规避加载顺序问题。

static NSBundle *(*g_origPLBundle)(id, SEL) = NULL;
static int g_plRetry = 0;

static NSBundle *MiYouLite_PLBundle(id self, SEL _cmd) {
    PSSpecifier *spec = nil;
    @try { spec = [self valueForKey:@"_specifier"]; } @catch (NSException *e) {}
    NSString *lazy = nil;
    if (spec && [spec respondsToSelector:@selector(propertyForKey:)]) {
        lazy = [spec propertyForKey:@"PSLazilyLoadedBundleKey"];
    }
    if ([lazy isKindOfClass:[NSString class]] &&
        [lazy rangeOfString:@"MiYouLitePrefs"].location != NSNotFound) {
        NSMutableArray *paths = [NSMutableArray arrayWithArray:@[
            @"/Library/PreferenceBundles/MiYouLitePrefs.bundle"]];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *appBase = @"/var/containers/Bundle/Application";
        if ([fm fileExistsAtPath:appBase]) {
            for (NSString *s in [fm contentsOfDirectoryAtPath:appBase error:nil] ?: @[]) {
                if ([s hasPrefix:@".jbroot"]) {
                    [paths addObject:[appBase stringByAppendingPathComponent:
                        [s stringByAppendingPathComponent:@"Library/PreferenceBundles/MiYouLitePrefs.bundle"]]];
                }
            }
        }
        for (NSString *p in paths) {
            NSBundle *b = [NSBundle bundleWithPath:p];
            if (b && [b pathForResource:@"Root" ofType:@"plist"]) {
                MYLLog(@"PLFallback: bundle redirected -> %@", p);
                return b;
            }
        }
    }
    return g_origPLBundle ? g_origPLBundle(self, _cmd) : nil;
}

static void MiYouLiteHookPL(void) {
    Class plClass = objc_getClass("PLCustomListController");
    if (!plClass) {
        if (g_plRetry++ < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ MiYouLiteHookPL(); });
        } else {
            MYLLog(@"PLFallback: PLCustomListController never appeared, giving up");
        }
        return;
    }
    if (g_origPLBundle) return; // 已安装
    MSHookMessageEx(plClass, @selector(bundle), (IMP)MiYouLite_PLBundle, (IMP *)&g_origPLBundle);
    MYLLog(@"PLFallback hook installed on PLCustomListController");
}
