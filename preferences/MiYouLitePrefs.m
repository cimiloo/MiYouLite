#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// 诊断日志：写文件，绕过系统 log 命令兼容性问题。
// 自动选择可用目录并建目录，确保 cat 一定有输出。
// ★ roothide 没有 /var/jb 目录，日志统一写到真实 rootfs 的 /tmp。
//   装后可在 NewTerm / Filza 执行：cat /tmp/miyoulite_prefs.log 查看。
#import <stdio.h>
static NSString *MYLLogPath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    // roothide 无 /var/jb；优先用真实 rootfs 的 /tmp（已验证 Preferences 可写、Filza 可见）
    NSArray *dirs = @[ @"/tmp", @"/var/mobile/Library/Logs", @"/var/tmp" ];
    NSString *d = nil;
    for (NSString *c in dirs) {
        // 目录已存在，或我们能在 roothide 下创建它 → 选它
        if ([fm fileExistsAtPath:c] ||
            [fm createDirectoryAtPath:c withIntermediateDirectories:YES attributes:nil error:nil]) {
            d = c; break;
        }
    }
    if (!d) d = @"/tmp";
    return [d stringByAppendingPathComponent:@"miyoulite_prefs.log"];
}
#define MYLLog(...) do { \
    NSString *__msg = [NSString stringWithFormat:__VA_ARGS__]; \
    NSLog(@"[MiYouLite] %@", __msg); \
    NSString *__p = MYLLogPath(); \
    FILE *__lf = fopen([__p UTF8String], "a"); \
    if (__lf) { fprintf(__lf, "[MiYouLite] %s\n", [__msg UTF8String]); fclose(__lf); } \
} while(0)

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
- (void)setProperty:(id)value forKey:(NSString *)key;
@end

// roothide-theos SDK 不含 Preferences 私有头 → 提供最小本地声明
@interface PSListController : UIViewController
- (NSString *)specifierPlistName;
- (NSArray *)specifiers;
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
- (NSBundle *)bundle;       // UIViewController 已声明，但编译器需见前向声明
@end

static NSString *const kMiYouLiteDomain = @"com.miyou.lite";
// 版本号需与 control 的 Version 字段、Tweak.xm 的日志版本串保持同步
static NSString *const kMiYouLiteVersion = @"1.2.13";
// roothide PreferenceLoader 存储 bundle 路径的 property key（与 prefs.xm 源码一致）
static NSString *const PLBundleKey = @"pl_bundle";
static NSString *const PSLazilyLoadedBundleKey = @"PSLazilyLoadedBundleKey";

#pragma mark - 跨进程共享配置（与 Tweak 共用：写到微信容器真实 Documents，经 /var/mobile/Containers 共享 symlink 跨进程可见）
// ★ v1.2.12：/rootfs 在微信沙盒不可访问、/var/mobile/Library/Preferences 又按 App 虚拟化，
//   故改为「微信自身容器 Documents/com.miyou.lite.plist」作为唯一共享文件：
//   微信读自己容器（固定可达）；设置面板用 LSApplicationProxy 找到微信容器真实路径写入同一文件。
static NSString *MiYouLiteWeChatContainerDocs(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    // ★ 关键修正（v1.2.13）：必须解析「Data 容器」而非「Bundle 容器」。
    //   微信 tweak 端用 NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,…)
    //   得到的是 Data 容器 <Data>/Application/<uuid>/Documents；之前误用 bundleURL
    //   （Bundle 容器 <Bundle>/Application/<uuid>/WeChat.app）再删尾巴，写到了错误目录，
    //   微信永远读不到 → 功能不生效。这里改用 dataContainerURL（真正的 Data 容器根）。
    Class LSApplicationProxy = objc_getClass("LSApplicationProxy");
    if (LSApplicationProxy && [LSApplicationProxy respondsToSelector:@selector(applicationProxyForIdentifier:)]) {
        id proxy = [LSApplicationProxy performSelector:@selector(applicationProxyForIdentifier:) withObject:@"com.tencent.xin"];
        if (proxy && [proxy respondsToSelector:@selector(dataContainerURL)]) {
            NSURL *dataURL = [proxy performSelector:@selector(dataContainerURL)];
            NSString *path = [dataURL path]; // .../Data/Application/<uuid>
            if (path.length) {
                return [path stringByAppendingPathComponent:@"Documents"];
            }
        }
    }
    // 方法2：枚举 Data 容器，按 MCMMetadataIdentifier 匹配 com.tencent.xin
    //   （.app 在 Bundle 容器，Data 容器里没有 .app，故不能按 .app/Info.plist 找，
    //    要看每个 UUID 下的 .com.apple.mobile_container_manager.metadata.plist）
    NSString *base = @"/var/mobile/Containers/Data/Application";
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *uuid in [fm contentsOfDirectoryAtPath:base error:nil] ?: @[]) {
        NSString *meta = [base stringByAppendingPathComponent:
            [uuid stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"]];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:meta];
        if ([[info objectForKey:@"MCMMetadataIdentifier"] isEqualToString:@"com.tencent.xin"]) {
            return [base stringByAppendingPathComponent:[uuid stringByAppendingPathComponent:@"Documents"]];
        }
    }
#pragma clang diagnostic pop
    return nil;
}
static void MiYouLiteWriteSharedConfig(NSDictionary *d) {
    if (!d) return;
    // ★ 候选写入路径（与微信读取优先级一致）：微信 Data 容器 Documents → 虚拟化兜底
    NSMutableArray *dirs = [NSMutableArray array];
    NSString *wxDocs = MiYouLiteWeChatContainerDocs();
    MYLLog(@"resolved WeChat data-container Documents = %@", wxDocs ?: @"(nil — 解析失败)");
    if (wxDocs) [dirs addObject:wxDocs];
    [dirs addObject:@"/var/mobile/Library/Preferences"];
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *dir in dirs) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *p = [dir stringByAppendingPathComponent:@"com.miyou.lite.plist"];
        if ([d writeToFile:p atomically:YES]) { MYLLog(@"shared config written -> %@", p); return; }
        MYLLog(@"write FAILED -> %@ (errno 占位)", p);
    }
    MYLLog(@"shared config write FAILED（所有候选路径均不可写）");
}

@interface MiYouLitePrefsController : PSListController
@end

@implementation MiYouLitePrefsController {
    BOOL _authed;
    NSArray *_mySpecifiers;
}

+ (void)initialize {
    MYLLog(@"controller class loaded: %@", NSStringFromClass(self));
}

// 把当前 CFPreferences 中的设置值镜像到共享文件，并发 Darwin 通知让微信热重载
- (void)miYouLite_mirrorAndNotify {
    CFStringRef domain = (__bridge CFStringRef)kMiYouLiteDomain;
    CFPropertyListRef v;
    BOOL anti = NO;
    v = CFPreferencesCopyValue(CFSTR("antiRevokeEnabled"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    anti = (v && CFGetTypeID(v)==CFBooleanGetTypeID()) ? (BOOL)CFBooleanGetValue((CFBooleanRef)v) : NO;
    if (v) CFRelease(v);
    BOOL hide = NO;
    v = CFPreferencesCopyValue(CFSTR("hideModeEnabled"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    hide = (v && CFGetTypeID(v)==CFBooleanGetTypeID()) ? (BOOL)CFBooleanGetValue((CFBooleanRef)v) : NO;
    if (v) CFRelease(v);
    NSString *pwd = @"";
    v = CFPreferencesCopyValue(CFSTR("password"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    pwd = (v && CFGetTypeID(v)==CFStringGetTypeID()) ? (__bridge_transfer NSString *)v : @"";
    if (v && CFGetTypeID(v)!=CFStringGetTypeID()) CFRelease(v);
    NSString *friends = @"";
    v = CFPreferencesCopyValue(CFSTR("hiddenFriends"), domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    friends = (v && CFGetTypeID(v)==CFStringGetTypeID()) ? (__bridge_transfer NSString *)v : @"";
    if (v && CFGetTypeID(v)!=CFStringGetTypeID()) CFRelease(v);

    NSDictionary *d = @{
        @"antiRevokeEnabled": @(anti),
        @"hideModeEnabled": @(hide),
        @"password": pwd ?: @"",
        @"hiddenFriends": friends ?: @""
    };
    MiYouLiteWriteSharedConfig(d);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.miyou.lite/settings-changed"), NULL,
        (__bridge CFDictionaryRef)d, TRUE);
    MYLLog(@"settings mirrored: anti=%d hide=%d pwd=%lu friends=%lu", anti, hide, (unsigned long)pwd.length, (unsigned long)friends.length);
}

// ═══════════════════════════════════════════════
// ★★★ 关键修复（bundle 来源）★★★
// roothide 的 PreferenceLoader 对 isController 条目，会把内部键 `PLBundleKey`
// 设成「入口 plist 所在目录(/Library/PreferenceLoader/Preferences)」而非我们的 bundle；
// PLCustomListController 的 bundle 方法也会回退到 PL 自身目录。若直接返回这些，
// PSListController 去该目录找 Resources/Root.plist 必然落空 → 一直空白。
// 正确来源：本类就定义在 MiYouLitePrefs.bundle 内，故 [super bundle] 即指向它；
// 并辅以 jbroot 动态定位兜底（roothide 无 /var/jb）。
// ═══════════════════════════════════════════════
- (NSBundle *)bundle {
    // 只接受「确实包含 Root.plist」的 bundle，杜绝误用 PLBundleKey 指向的目录。
    NSFileManager *fm = [NSFileManager defaultManager];
    NSBundle *(^hasRoot)(NSBundle *) = ^NSBundle *(NSBundle *b) {
        if (b && [b pathForResource:@"Root" ofType:@"plist"]) return b;
        return nil;
    };
    NSBundle *(^checkPath)(NSString *) = ^NSBundle *(NSString *p) {
        return hasRoot([NSBundle bundleWithPath:p]);
    };

    NSBundle *b = [super bundle];
    if (hasRoot(b)) {
        MYLLog(@"bundle(super): %@", b.bundlePath);
        return b;
    }

    // 兜底：roothide 下 bundle 实际装在 jbroot
    // (/var/containers/Bundle/Application/.jbroot-*/Library/PreferenceBundles/)。
    // ★ roothide 没有 /var/jb，这里动态定位 jbroot，不再硬编码 /var/jb 路径。
    NSBundle *cand = checkPath(@"/Library/PreferenceBundles/MiYouLitePrefs.bundle");
    if (cand) { MYLLog(@"bundle(fixed): %@", cand.bundlePath); return cand; }

    NSString *jbrootBase = @"/var/containers/Bundle/Application/";
    for (NSString *s in ([fm contentsOfDirectoryAtPath:jbrootBase error:nil] ?: @[])) {
        if ([s hasPrefix:@".jbroot-"]) {
            NSString *p = [jbrootBase stringByAppendingPathComponent:
                [s stringByAppendingPathComponent:@"Library/PreferenceBundles/MiYouLitePrefs.bundle"]];
            NSBundle *c = checkPath(p);
            if (c) { MYLLog(@"bundle(fixed): %@", c.bundlePath); return c; }
        }
    }

    MYLLog(@"WARNING: bundle unresolved, fall back to super");
    return [super bundle];
}

// 告诉 PSListController 用 Root.plist 驱动 UI
- (NSString *)specifierPlistName {
    return @"Root";
}

// ★★★ 关键修复 ★★★
// PSListController 基类不会自动从 Root.plist 加载 specifiers，它直接返回内部
// _specifiers ivar（初始为 nil）。必须显式调用 loadSpecifiersFromPlistName:target:
// 并把结果填进 _specifiers，否则面板永远空白（specifiers count = 0）。
//
// 注意：这里只负责「加载」specifiers；每个 specifier 的 取值/存值 完全交给
// PSListController 内置的 readPreferenceValue:/setPreferenceValue:forSpecifier:，
// 框架会按 Root.plist 里配置的 defaults(=com.miyou.lite) + key 走系统 CFPreferences。
// 切勿自己再 override 这两个方法 —— 之前在内部访问 specifier.identifier /
// propertyDictionary 会在 iOS 16 真实 PSSpecifier 上触发 unrecognized selector 崩溃。
- (NSArray *)specifiers {
    if (!_mySpecifiers) {
        _mySpecifiers = [self loadSpecifiersFromPlistName:[self specifierPlistName] target:self];
        // 动态修正底部版本信息，避免 plist 硬编码版本号与代码失同步（之前漏改成旧版号）
        for (PSSpecifier *sp in _mySpecifiers) {
            NSString *ft = [sp propertyForKey:@"footerText"];
            if (ft && [ft rangeOfString:@"MiYouLite"].location != NSNotFound) {
                [sp setProperty:[NSString stringWithFormat:@"MiYouLite %@ · roothide · 微信 8.0.75", kMiYouLiteVersion]
                         forKey:@"footerText"];
            }
        }
        // 同步基类 _specifiers ivar：部分 PSListController 内部直接读该 ivar 而非 getter
        if (_mySpecifiers) {
            @try { [self setValue:_mySpecifiers forKey:@"_specifiers"]; }
            @catch (NSException *e) { MYLLog(@"set _specifiers ivar failed: %@", e); }
        }
    }
    MYLLog(@"specifiers count = %lu, bundle=%@",
           (unsigned long)(_mySpecifiers ? _mySpecifiers.count : 0), [self bundle]);
    return _mySpecifiers;
}

- (void)viewDidLoad {
    MYLLog(@"viewDidLoad, bundle=%@", [self bundle]);
    [self miYouLite_mirrorAndNotify]; // 首次打开即把当前值镜像到共享文件
    [super viewDidLoad];
}

- (void)viewWillDisappear:(BOOL)animated {
    [self miYouLite_mirrorAndNotify]; // 离开设置页时镜像最新值并通知微信
    [super viewWillDisappear:animated];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    MYLLog(@"viewWillAppear");

    NSString *pwd = (__bridge_transfer NSString *)CFPreferencesCopyValue(
        CFSTR("password"), (__bridge CFStringRef)kMiYouLiteDomain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    if (pwd.length > 0 && !_authed) {
        [self performSelector:@selector(showAuthAlert) withObject:nil afterDelay:0.3];
    }
}

- (void)reloadSpecifiers {
    // 清空缓存，下一次 specifiers getter 会重新从 Root.plist 加载
    _mySpecifiers = nil;
    [super reloadSpecifiers];
}

// ── 密码弹窗 ──
- (void)showAuthAlert {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"MiYouLite 已锁定"
                         message:@"请输入密码以访问设置"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.secureTextEntry = YES;
        tf.placeholder = @"密码";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text ?: @"";
        NSString *saved = (__bridge_transfer NSString *)CFPreferencesCopyValue(
            CFSTR("password"), (__bridge CFStringRef)kMiYouLiteDomain,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        if (saved.length > 0 && [input isEqualToString:saved]) {
            _authed = YES;
            [self reloadSpecifiers];
        } else {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// ── 设置/修改密码按钮回调 ──
- (void)setPassword:(PSSpecifier *)specifier {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"设置密码"
                         message:@"输入新密码（留空则清除密码保护）"
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.secureTextEntry = YES;
        tf.placeholder = @"新密码";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        NSString *input = alert.textFields.firstObject.text ?: @"";
        CFPreferencesSetValue(CFSTR("password"),
                              input.length > 0 ? (__bridge CFStringRef)input : CFSTR(""),
                              (__bridge CFStringRef)kMiYouLiteDomain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        CFPreferencesSynchronize((__bridge CFStringRef)kMiYouLiteDomain,
                                 kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
        [self miYouLite_mirrorAndNotify];
        _authed = YES;
        [self reloadSpecifiers];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

// ── 移除密码按钮回调 ──
- (void)removePassword:(PSSpecifier *)specifier {
    CFPreferencesSetValue(CFSTR("password"), CFSTR(""),
                          (__bridge CFStringRef)kMiYouLiteDomain,
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    CFPreferencesSynchronize((__bridge CFStringRef)kMiYouLiteDomain,
                             kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    [self miYouLite_mirrorAndNotify];
    [self reloadSpecifiers];
}

@end
