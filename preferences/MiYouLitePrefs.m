#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 诊断日志：进入设置页若仍异常，可在 Mac 上 `log stream | grep MiYouLite` 抓取
#define MYLLog(...) NSLog(@"[MiYouLite] " __VA_ARGS__)

@class PSSpecifier;

// roothide-theos SDK 不含 Preferences 私有头 → 提供最小本地声明
@interface PSListController : UIViewController
- (NSString *)specifierPlistName;
- (NSArray *)specifiers;
- (void)reloadSpecifiers;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
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
- (NSBundle *)bundle {
    // 优先从 specifier 取 PL 存的 lazy-load bundle 路径
    PSSpecifier *spec = [self valueForKey:@"_specifier"];  // PSListController 内部 ivar
    if (spec) {
        // 尝试 PSLazilyLoadedBundleKey（PL 对 isController+isBundle 条目设的）
        id lazyPath = [spec propertyForKey:PSLazilyLoadedBundleKey];
        if (lazyPath) {
            NSBundle *b = [NSBundle bundleWithPath:lazyPath];
            if (b) {
                MYLLog(@"bundle from PSLazilyLoadedBundleKey: %@", b);
                return b;
            }
        }
        // 尝试 PLBundleKey（PLCustomListController 用的方式）
        id plBundle = [spec propertyForKey:PLBundleKey];
        if ([plBundle isKindOfClass:[NSBundle class]]) {
            MYLLog(@"bundle from PLBundleKey: %@", plBundle);
            return plBundle;
        }
    }

    // 兜底：直接按已知路径加载
    NSBundle *direct = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/MiYouLitePrefs.bundle"];
    if (direct && [direct isLoaded]) {
        MYLLog(@"bundle from direct path (loaded): %@", direct);
        return direct;
    }
    direct = [NSBundle bundleWithPath:@"/Library/PreferenceBundles/MiYouLitePrefs.bundle"];
    if (direct) {
        MYLLog(@"bundle from direct path: %@", direct);
        return direct;
    }

    MYLLog(@"WARNING: all bundle resolution failed, falling back to super");
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
