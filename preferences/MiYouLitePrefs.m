#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 诊断日志：写文件，绕过系统 log 命令兼容性问题。
// 自动选择可用目录并建目录，确保 cat 一定有输出。
// 装后可在 NewTerm 执行：cat /var/jb/tmp/miyoulite_prefs.log 查看（或 /tmp/...）
#import <stdio.h>
static NSString *MYLLogPath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *dirs = @[ @"/var/jb/tmp", @"/tmp", @"/var/tmp" ];
    NSString *d = nil;
    for (NSString *c in dirs) { if ([fm fileExistsAtPath:c]) { d = c; break; } }
    if (!d) { d = @"/var/jb/tmp"; [fm createDirectoryAtPath:d withIntermediateDirectories:YES attributes:nil error:nil]; }
    return [d stringByAppendingPathComponent:@"miyoulite_prefs.log"];
}
#define MYLLog(...) do { \
    NSString *__msg = [NSString stringWithFormat:__VA_ARGS__]; \
    NSLog(@"[MiYouLite] %@", __msg); \
    NSString *__p = MYLLogPath(); \
    FILE *__lf = fopen([__p UTF8String], "a"); \
    if (__lf) { fprintf(__lf, "[MiYouLite] %s\n", [__msg UTF8String]); fclose(__lf); } \
} while(0)

@class PSSpecifier;

// roothide-theos SDK 不含 Preferences 私有头 → 提供最小本地声明
@interface PSListController : UIViewController
- (NSString *)specifierPlistName;
- (NSArray *)specifiers;
- (void)reloadSpecifiers;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
- (NSBundle *)bundle;       // UIViewController 已声明，但编译器需见前向声明
@end

@interface PSSpecifier : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, retain) id propertyDictionary;
// roothide PL 在 specifier 上存 bundle 引用的 key
- (id)propertyForKey:(NSString *)key;
@end

static NSString *const kMiYouLiteDomain = @"com.miyou.lite";
// roothide PreferenceLoader 存储 bundle 路径的 property key（与 prefs.xm 源码一致）
static NSString *const PLBundleKey = @"pl_bundle";
static NSString *const PSLazilyLoadedBundleKey = @"PSLazilyLoadedBundleKey";

@interface MiYouLitePrefsController : PSListController
@end

@implementation MiYouLitePrefsController {
    BOOL _authed;
}

+ (void)initialize {
    MYLLog(@"controller class loaded: %@", NSStringFromClass(self));
}

// ═══════════════════════════════════════════════
// ★★★ 关键修复 ★★★
// roothide 的 PLCustomListController 重写了此方法返回正确的 NSBundle。
// 我们的子类也必须重写，否则 [self bundle] 返回 nil/错误 →
// PSListController 找不到 Resources/Root.plist → 空白页！
// ═══════════════════════════════════════════════
// ═══════════════════════════════════════════════
// ★★★ 关键修复 ★★★
// roothide 的 PreferenceLoader 对 isController 条目，会把内部键 `PLBundleKey`
// 设成「入口 plist 所在目录(/Library/PreferenceLoader/Preferences)」而非我们的 bundle！
// 若直接返回它，PSListController 去该目录找 Resources/Root.plist 必然落空 → 一直空白。
// 正确来源：基类 PSListController 依据 bundleForClass（本类就定义在我们的 bundle 内）
// 或 specifier 关联的已加载 bundle，二者都指向 MiYouLitePrefs.bundle。
// ═══════════════════════════════════════════════
- (NSBundle *)bundle {
    // 只接受「确实包含 Root.plist」的 bundle，杜绝误用 PLBundleKey 指向的目录。
    NSBundle *(^hasRoot)(NSBundle *) = ^NSBundle *(NSBundle *b) {
        if (b && [b pathForResource:@"Root" ofType:@"plist"]) return b;
        return nil;
    };

    NSBundle *b = [super bundle];
    if (hasRoot(b)) {
        MYLLog(@"bundle(super): %@", b.bundlePath);
        return b;
    }

    // 兜底：roothide 下 bundle 实际装在 /var/jb/Library/PreferenceBundles/
    for (NSString *p in @[
        @"/Library/PreferenceBundles/MiYouLitePrefs.bundle",
        @"/var/jb/Library/PreferenceBundles/MiYouLitePrefs.bundle"]) {
        NSBundle *cand = [NSBundle bundleWithPath:p];
        if (hasRoot(cand)) {
            MYLLog(@"bundle(fixed): %@", cand.bundlePath);
            return cand;
        }
    }

    MYLLog(@"WARNING: bundle unresolved, fall back to super");
    return [super bundle];
}

// 告诉 PSListController 用 Root.plist 驱动 UI
- (NSString *)specifierPlistName {
    return @"Root";
}

// 日志透传，不改变行为
- (NSArray *)specifiers {
    NSArray *s = [super specifiers];
    MYLLog(@"specifiers count = %lu, bundle=%@",
           (unsigned long)s.count, [self bundle]);
    return s;
}

- (void)viewDidLoad {
    MYLLog(@"viewDidLoad, bundle=%@", [self bundle]);
    [super viewDidLoad];
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
    [super reloadSpecifiers];
}

// ── 默认 get/set 回调 ──
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = specifier.identifier ?: specifier.propertyDictionary[@"key"];
    if (!key) return nil;

    CFPropertyListRef val = CFPreferencesCopyValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)kMiYouLiteDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);

    if (!val) {
        id defVal = specifier.propertyDictionary[@"default"];
        return defVal ?: @"";
    }
    return (__bridge_transfer id)val;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = specifier.identifier ?: specifier.propertyDictionary[@"key"];
    if (!key) return;

    CFPreferencesSetValue(
        (__bridge CFStringRef)key,
        (__bridge CFStringRef)(value ?: @""),
        (__bridge CFStringRef)kMiYouLiteDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);

    CFPreferencesSynchronize(
        (__bridge CFStringRef)kMiYouLiteDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost);

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.miyou.lite/settings-changed"),
        NULL, NULL, TRUE);
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
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                              CFSTR("com.miyou.lite/settings-changed"),
                                              NULL, NULL, TRUE);
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
    [self reloadSpecifiers];
}

@end
