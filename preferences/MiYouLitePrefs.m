#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// 诊断日志：进入设置页若仍异常，可在 Mac 上 `log stream | grep MiYouLite` 抓取
#define MYLLog(...) NSLog(@"[MiYouLite] " __VA_ARGS__)

@class PSSpecifier;

// roothide-theos SDK 不含 Preferences 私有头 → 提供最小本地声明（仅声明用到的方法）
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
@end

static NSString *const kMiYouLiteDomain = @"com.miyou.lite";

@interface MiYouLitePrefsController : PSListController
@end

@implementation MiYouLitePrefsController {
    BOOL _authed;
}

+ (void)initialize {
    MYLLog(@"controller class loaded: %@", NSStringFromClass(self));
}

// 强制使用 Root.plist（原生解析，字符串 cell 类型由系统正确处理）
- (NSString *)specifierPlistName {
    return @"Root";
}

// 仅做计数日志，不改变父类行为
- (NSArray *)specifiers {
    NSArray *s = [super specifiers];
    MYLLog(@"specifiers count = %lu (bundle=%@)", (unsigned long)s.count, [self bundle]);
    return s;
}

- (void)viewDidLoad {
    MYLLog(@"viewDidLoad");
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

// ── 默认 get/set 回调（plist 中带 key 且无显式 set/get 时由 PSListController 自动调用）──
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
