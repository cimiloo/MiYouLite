#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#pragma mark - 配置管理器（本地 plist 持久化隐藏列表/密码）

static NSString *const kMiYouLitePlistPath = @"/var/mobile/Library/Preferences/com.miyou.lite.plist";

@interface MiYouLiteManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, assign) BOOL antiRevokeEnabled;
@property (nonatomic, assign) BOOL hideModeEnabled;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSMutableArray *hiddenFriends; // wxid 列表
@property (nonatomic, strong) NSMutableArray *hiddenRooms;   // room id 列表
@property (nonatomic, assign) BOOL isUnlocked;               // 密码验证通过后为 YES
- (BOOL)isFriendHidden:(NSString *)usrName;
- (BOOL)isRoomHidden:(NSString *)roomName;
- (void)save;
- (void)load;
@end

@implementation MiYouLiteManager
+ (instancetype)sharedManager {
    static MiYouLiteManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MiYouLiteManager alloc] init];
        [instance load];
    });
    return instance;
}
- (instancetype)init {
    self = [super init];
    if (self) {
        _hiddenFriends = [NSMutableArray array];
        _hiddenRooms = [NSMutableArray array];
        _isUnlocked = NO;
    }
    return self;
}
- (void)load {
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:kMiYouLitePlistPath];
    if (dict) {
        self.antiRevokeEnabled = [dict[@"antiRevokeEnabled"] boolValue];
        self.hideModeEnabled   = [dict[@"hideModeEnabled"] boolValue];
        self.password          = dict[@"password"] ?: @"";
        self.hiddenFriends     = [NSMutableArray arrayWithArray:dict[@"hiddenFriends"] ?: @[]];
        self.hiddenRooms       = [NSMutableArray arrayWithArray:dict[@"hiddenRooms"] ?: @[]];
    }
}
- (void)save {
    NSDictionary *dict = @{
        @"antiRevokeEnabled": @(self.antiRevokeEnabled),
        @"hideModeEnabled":   @(self.hideModeEnabled),
        @"password":          self.password ?: @"",
        @"hiddenFriends":     self.hiddenFriends ?: @[],
        @"hiddenRooms":       self.hiddenRooms ?: @[]
    };
    [dict writeToFile:kMiYouLitePlistPath atomically:YES];
}
- (BOOL)isFriendHidden:(NSString *)usrName {
    if (!self.hideModeEnabled || self.isUnlocked) return NO;
    return [self.hiddenFriends containsObject:usrName ?: @""];
}
- (BOOL)isRoomHidden:(NSString *)roomName {
    if (!self.hideModeEnabled || self.isUnlocked) return NO;
    return [self.hiddenRooms containsObject:roomName ?: @""];
}
@end

// 监听解锁后刷新会话列表
static void MiYouLiteForceReloadSessions(void) {
    Class cls = objc_getClass("MMNewSessionMgr");
    if (!cls) return;
    id mgr = [cls performSelector:@selector(getSessionMgr)] ?: nil;
    if (!mgr) {
        // 退而求其次：直接发通知让微信自己刷新
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
    // 开启防撤回时，拦截撤回（原插件逻辑：不调用 %orig，使消息保留）
    if ([MiYouLiteManager sharedManager].antiRevokeEnabled) {
        NSLog(@"[MiYouLite] 拦截撤回: %@", arg1);
        return; // 不执行原撤回逻辑
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
    if ([[MiYouLiteManager sharedManager] isFriendHidden:usrName]) {
        return nil; // 隐藏单个联系人
    }
    return contact;
}
- (id)getAllContacts {
    id contacts = %orig;
    if (![MiYouLiteManager sharedManager].hideModeEnabled) return contacts;
    if ([MiYouLiteManager sharedManager].isUnlocked) return contacts;
    if (![contacts isKindOfClass:[NSArray class]]) return contacts;
    NSMutableArray *filtered = [NSMutableArray array];
    for (id contact in contacts) {
        NSString *usrName = @"";
        @try { usrName = [contact valueForKey:@"m_nsUsrName"]; } @catch (NSException *e) {}
        if (![[MiYouLiteManager sharedManager] isFriendHidden:usrName]) {
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
    // 计算需要隐藏的会话数量，从总数中扣除
    int hidden = 0;
    for (int i = 0; i < count; i++) {
        id session = g_origGetSessionAtIndex(self, @selector(GetSessionAtIndex:), i);
        if (!session) continue;
        NSString *name = @"";
        @try { name = [session valueForKey:@"m_nsUserName"]; } @catch (NSException *e) {}
        if ([mgr isFriendHidden:name] || [mgr isRoomHidden:name]) hidden++;
    }
    return MAX(0, count - hidden);
}

static id MiYouLite_GetSessionAtIndex(id self, SEL _cmd, int arg1) {
    MiYouLiteManager *mgr = [MiYouLiteManager sharedManager];
    if (!mgr.hideModeEnabled || mgr.isUnlocked) {
        return g_origGetSessionAtIndex(self, _cmd, arg1);
    }
    // 跳过被隐藏的会话：在 original 序列中顺序查找第 arg1 个未隐藏会话
    int count = g_origGetSessionCount(self, @selector(GetSessionCount));
    int skipped = 0;
    for (int i = 0; i < count; i++) {
        id session = g_origGetSessionAtIndex(self, @selector(GetSessionAtIndex:), i);
        if (!session) continue;
        NSString *name = @"";
        @try { name = [session valueForKey:@"m_nsUserName"]; } @catch (NSException *e) {}
        if ([mgr isFriendHidden:name] || [mgr isRoomHidden:name]) { skipped++; continue; }
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
            // 30 秒后自动重新锁定（退出搜索框效果）
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                mgr.isUnlocked = NO;
                MiYouLiteForceReloadSessions();
            });
        }
    }
}
%end

#pragma mark - 构造函数：安装 MMNewSessionMgr 手动 hook

%ctor {
    NSLog(@"[MiYouLite] 插件已加载 - 版本 1.1.0 (微信 8.0.75)");
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
    // 解锁/锁定后刷新（微信若监听该通知则生效）
    [[NSNotificationCenter defaultCenter] addObserverForName:@"MiYouLiteNeedReloadSession"
                                                       object:nil queue:nil
                                                  usingBlock:^(NSNotification *note) {
        MiYouLiteForceReloadSessions();
    }];
}
