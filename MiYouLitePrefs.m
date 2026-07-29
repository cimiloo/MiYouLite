#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@class PSSpecifier;

// roothide-theos SDK 不含 Preferences 私有头，提供 PSListController 最小本地声明。
// 运行期使用系统真实的 PSListController（动态派发）。
@interface PSListController : UIViewController
// iOS 全版本：viewDidLoad 时调此方法填充内部 _specifiers ivar（关键！不能只在子类 getter 里缓存）
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target;
- (void)reloadSpecifiers;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (id)readPreferenceValue:(PSSpecifier *)specifier;
@end

// PSSpecifier 创建辅助（避免依赖私有头）
// 真实签名：+ (id)preferenceSpecifierNamed:(id) target:(id) set:(SEL) get:(SEL) detail:(Class) cell:(id) edit:(long long)
@interface PSSpecifier : NSObject
+ (id)preferenceSpecifierNamed:(NSString *)name target:(id)target set:(SEL)set get:(SEL)get detail:(Class)detail cell:(NSString *)cellType edit:(NSInteger)edit;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, retain) id propertyDictionary;
@end

static NSString *const kMiYouLiteDomain = @"com.miyou.lite";

@interface MiYouLitePrefsController : PSListController
@end

@implementation MiYouLitePrefsController {
    BOOL _authed;
    NSArray *_builtSpecs;   // 构建结果缓存，避免重复构建
}

// ── 关键修复：重写 loadSpecifiersFromPlistName:target: 返回代码构建的数组 ──
// iOS 16 的 PSListController 在 viewDidLoad 时调用它来填充内部 _specifiers ivar；
// 子类若只在自己的 specifiers getter 里缓存，父类的 _specifiers 永远是 nil → 空白页。
// 重写此方法，父类就能拿到我们的 specifiers 并正确填充 _specifiers。
// ── specifiers getter（双保险）：走父类 getter（其内部会调 loadSpecifiersFromPlistName: 填充 _specifiers）；
// 若父类路径未填充（极端情况），兜底构建并通过 KVC 同步到父类 _specifiers ivar。──
- (NSArray *)specifiers {
    if (_builtSpecs) return _builtSpecs;

    NSArray *parentSpecs = [super specifiers];
    if (parentSpecs.count > 0) {
        _builtSpecs = parentSpecs;
        return _builtSpecs;
    }

    _builtSpecs = [self buildSpecifiers];
    // KVC 同步到父类 _specifiers ivar（iOS 16 直接读 ivar 的场景）
    @try { [self setValue:_builtSpecs forKey:@"specifiers"]; }
    @catch (NSException *e) { /* 父类无此 ivar/setter 时忽略 */ }
    return _builtSpecs;
}

// 实际构建代码（单一数据源）
- (NSArray *)buildSpecifiers {
    NSMutableArray *specs = [NSMutableArray array];

    [specs addObject:[self groupSpecWithLabel:@"功能开关"
                                       footer:@"防撤回：拦截对方撤回消息。密友隐藏：在列表/通讯录中隐藏指定联系人，需配合下方密码使用。"]];

    [specs addObject:[self switchSpecWithLabel:@"防撤回" key:@"antiRevokeEnabled" default:NO]];
    [specs addObject:[self switchSpecWithLabel:@"密友隐藏" key:@"hideModeEnabled" default:NO]];

    [specs addObject:[self groupSpecWithLabel:@"密友列表"
                                       footer:@"每行填一个 wxid（如 wxid_xxxxxx），隐藏后该联系人的会话与通讯录入口将不显示。多个 wxid 换行分隔。"]];

    [specs addObject:[self textSpecWithLabel:@"密友 wxid" key:@"hiddenFriends" default:@""]];

    [specs addObject:[self groupSpecWithLabel:@"密码保护"
                                       footer:@"设置密码后，进入本设置页需先验证。留空可清除密码保护。忘记密码请重装插件。"]];

    [specs addObject:[self buttonSpecWithLabel:@"设置 / 修改密码" action:@selector(setPassword:)]];
    [specs addObject:[self buttonSpecWithLabel:@"移除密码" action:@selector(removePassword:)]];

    [specs addObject:[self groupSpecWithLabel:nil
                                       footer:@"MiYouLite 1.2.2 · roothide · 微信 8.0.75"]];

    return specs;
}

// 保留 loadSpecifiersFromPlistName: 重载（父类标准加载路径会走到这里）
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target {
    if (!_builtSpecs) _builtSpecs = [self buildSpecifiers];
    return _builtSpecs;
}

// 密码验证通过后刷新（父类会重新走 loadSpecifiersFromPlistName:）
- (void)reloadSpecifiers {
    [super reloadSpecifiers];
}

// ── 密码验证（进入页面时触发）──
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    NSString *pwd = (__bridge_transfer NSString *)CFPreferencesCopyValue(
        CFSTR("password"), (__bridge CFStringRef)kMiYouLiteDomain,
        kCFPreferencesCurrentUser, kCFPreferencesAnyHost);

    if (pwd.length > 0 && !_authed) {
        [self performSelector:@selector(showAuthAlert) withObject:nil afterDelay:0.3];
    }
}

// ── Specifier 工厂方法（target 必须是 self，按钮 action 才能派发到本类）──

- (PSSpecifier *)groupSpecWithLabel:(NSString *)label footer:(NSString *)footer {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:self
                                                          set:NULL
                                                          get:NULL
                                                        detail:Nil
                                                         cell:@"PSGroupCell"
                                                         edit:0];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (label) dict[@"label"] = label;
    if (footer) dict[@"footerText"] = footer;
    spec.propertyDictionary = dict;
    return spec;
}

- (PSSpecifier *)switchSpecWithLabel:(NSString *)label key:(NSString *)key default:(BOOL)defVal {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:self
                                                          set:@selector(setPreferenceValue:specifier:)
                                                          get:@selector(readPreferenceValue:)
                                                        detail:Nil
                                                         cell:@"PSSwitchCell"
                                                         edit:0];
    spec.identifier = key;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"key"] = key;
    dict[@"default"] = @(defVal);
    dict[@"PostNotification"] = @"com.miyou.lite/settings-changed";
    dict[@"label"] = label;
    spec.propertyDictionary = dict;
    return spec;
}

- (PSSpecifier *)textSpecWithLabel:(NSString *)label key:(NSString *)key default:(NSString *)defVal {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:self
                                                          set:@selector(setPreferenceValue:specifier:)
                                                          get:@selector(readPreferenceValue:)
                                                        detail:Nil
                                                         cell:@"PSEditTextViewCell"
                                                         edit:0];
    spec.identifier = key;
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"key"] = key;
    dict[@"default"] = defVal ?: @"";
    dict[@"PostNotification"] = @"com.miyou.lite/settings-changed";
    dict[@"label"] = label;
    spec.propertyDictionary = dict;
    return spec;
}

- (PSSpecifier *)buttonSpecWithLabel:(NSString *)label action:(SEL)action {
    PSSpecifier *spec = [PSSpecifier preferenceSpecifierNamed:label
                                                       target:self
                                                          set:action
                                                          get:NULL
                                                        detail:Nil
                                                         cell:@"PSButtonCell"
                                                         edit:0];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"action"] = NSStringFromSelector(action);
    dict[@"label"] = label;
    spec.propertyDictionary = dict;
    return spec;
}

// ── CFPreferences 读写桥接（供 PSSpecifier 的 get/set 回调使用）──
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
