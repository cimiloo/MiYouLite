#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

#pragma mark - 配置管理器

static NSString *const kMiYouLitePlistPath = @"/var/mobile/Library/Preferences/com.miyoulite.plist";

@interface MiYouLiteManager : NSObject
+ (instancetype)sharedManager;
@property (nonatomic, assign) BOOL antiRevokeEnabled;
@property (nonatomic, assign) BOOL hideModeEnabled;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, strong) NSMutableArray *hiddenFriends;
@property (nonatomic, strong) NSMutableArray *hiddenRooms;
@property (nonatomic, assign) BOOL isUnlocked; // 密码验证通过后为 YES
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
        self.hideModeEnabled = [dict[@"hideModeEnabled"] boolValue];
        self.password = dict[@"password"] ?: @"";
        self.hiddenFriends = [NSMutableArray arrayWithArray:dict[@"hiddenFriends"] ?: @[]];
        self.hiddenRooms = [NSMutableArray arrayWithArray:dict[@"hiddenRooms"] ?: @[]];
    }
}

- (void)save {
    NSDictionary *dict = @{
        @"antiRevokeEnabled": @(self.antiRevokeEnabled),
        @"hideModeEnabled": @(self.hideModeEnabled),
        @"password": self.password ?: @"",
        @"hiddenFriends": self.hiddenFriends ?: @[],
        @"hiddenRooms": self.hiddenRooms ?: @[]
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

#pragma mark - 设置界面

@interface MiYouLiteSettingViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *sections;
@end

@implementation MiYouLiteSettingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MiYouLite";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
    
    self.sections = @[
        @{@"title": @"防撤回", @"cells": @[
            @{@"label": @"开启防撤回", @"type": @"switch", @"key": @"antiRevokeEnabled"}
        ]},
        @{@"title": @"密友隐藏", @"cells": @[
            @{@"label": @"开启隐藏模式", @"type": @"switch", @"key": @"hideModeEnabled"},
            @{@"label": @"设置密码", @"type": @"push", @"vc": @"password"},
            @{@"label": @"管理隐藏好友", @"type": @"push", @"vc": @"friends"},
            @{@"label": @"管理隐藏群聊", @"type": @"push", @"vc": @"rooms"}
        ]}
    ];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.sections[section][@"cells"] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section][@"title"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    
    NSDictionary *cellData = self.sections[indexPath.section][@"cells"][indexPath.row];
    cell.textLabel.text = cellData[@"label"];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    if ([cellData[@"type"] isEqualToString:@"switch"]) {
        UISwitch *sw = [[UISwitch alloc] init];
        NSString *key = cellData[@"key"];
        sw.on = [[MiYouLiteManager sharedManager] valueForKey:key];
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        objc_setAssociatedObject(sw, @"key", key, OBJC_ASSOCIATION_RETAIN);
        cell.accessoryView = sw;
    } else if ([cellData[@"type"] isEqualToString:@"push"]) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    NSString *key = objc_getAssociatedObject(sender, @"key");
    [[MiYouLiteManager sharedManager] setValue:@(sender.on) forKey:key];
    [[MiYouLiteManager sharedManager] save];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *cellData = self.sections[indexPath.section][@"cells"][indexPath.row];
    NSString *vcType = cellData[@"vc"];
    if ([vcType isEqualToString:@"password"]) {
        [self showPasswordSetting];
    } else if ([vcType isEqualToString:@"friends"]) {
        [self showFriendPicker];
    } else if ([vcType isEqualToString:@"rooms"]) {
        [self showRoomPicker];
    }
}

- (void)showPasswordSetting {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"设置密码" message:@"输入密码后，在微信搜索框输入密码可显示隐藏的联系人" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"请输入密码";
        tf.secureTextEntry = YES;
    }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"确认密码";
        tf.secureTextEntry = YES;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *pwd = alert.textFields[0].text ?: @"";
        NSString *confirm = alert.textFields[1].text ?: @"";
        if ([pwd isEqualToString:confirm] && pwd.length > 0) {
            [MiYouLiteManager sharedManager].password = pwd;
            [[MiYouLiteManager sharedManager] save];
            UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"成功" message:@"密码设置成功" preferredStyle:UIAlertControllerStyleAlert];
            [ok addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:ok animated:YES completion:nil];
        } else {
            UIAlertController *fail = [UIAlertController alertControllerWithTitle:@"错误" message:@"密码不一致或为空" preferredStyle:UIAlertControllerStyleAlert];
            [fail addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:fail animated:YES completion:nil];
        }
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFriendPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"管理隐藏好友" message:@"输入好友的微信号（wxid），用逗号分隔" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"wxid_xxx, wxid_yyy";
        tf.text = [[MiYouLiteManager sharedManager].hiddenFriends componentsJoinedByString:@", "];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields[0].text ?: @"";
        NSArray *ids = [text componentsSeparatedByString:@","];
        NSMutableArray *cleaned = [NSMutableArray array];
        for (NSString *wxid in ids) {
            NSString *trimmed = [wxid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length > 0) [cleaned addObject:trimmed];
        }
        [MiYouLiteManager sharedManager].hiddenFriends = cleaned;
        [[MiYouLiteManager sharedManager] save];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRoomPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"管理隐藏群聊" message:@"输入群聊的 ID，用逗号分隔" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"room_id_1, room_id_2";
        tf.text = [[MiYouLiteManager sharedManager].hiddenRooms componentsJoinedByString:@", "];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *text = alert.textFields[0].text ?: @"";
        NSArray *ids = [text componentsSeparatedByString:@","];
        NSMutableArray *cleaned = [NSMutableArray array];
        for (NSString *rid in ids) {
            NSString *trimmed = [rid stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (trimmed.length > 0) [cleaned addObject:trimmed];
        }
        [MiYouLiteManager sharedManager].hiddenRooms = cleaned;
        [[MiYouLiteManager sharedManager] save];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - 注入微信设置入口

#import <objc/runtime.h>

%hook MMUIViewController
- (void)viewDidLoad {
    %orig;
    // 识别微信的"我"页面，注入设置入口
    NSString *className = NSStringFromClass([self class]);
    if ([className isEqualToString:@"MMNewSettingViewController"] ||
        [className isEqualToString:@"SettingViewController"] ||
        [className isEqualToString:@"NewSettingViewController"]) {
        // 在设置页面注入入口的代码
        // 通过 swizzle 或直接修改 tableView 数据源
        NSLog(@"[MiYouLite] 检测到设置页面: %@", className);
    }
}
%end

#pragma mark - 防撤回

%hook CMessageMgr
- (void)onRevokeMsg:(id)arg1 {
    %orig;
    if (![MiYouLiteManager sharedManager].antiRevokeEnabled) return;
    NSLog(@"[MiYouLite] 拦截到撤回消息");
    // 保存被撤回消息的内容
    // 通过 MessageService 或直接读取消息数据
    // 然后显示在界面上
}
%end

#pragma mark - 密友 - 过滤联系人列表

%hook CContactMgr
- (id)getContact:(id)arg1 {
    id contact = %orig;
    if (!contact) return nil;
    // 获取联系人 wxid
    NSString *usrName = @"";
    @try {
        usrName = [contact valueForKey:@"m_nsUsrName"];
    } @catch (NSException *e) {}
    if ([[MiYouLiteManager sharedManager] isFriendHidden:usrName]) {
        return nil;
    }
    return contact;
}

- (id)getAllContacts {
    id contacts = %orig;
    if (![MiYouLiteManager sharedManager].hideModeEnabled) return contacts;
    if ([MiYouLiteManager sharedManager].isUnlocked) return contacts;
    
    // 过滤联系人列表
    NSMutableArray *filtered = [NSMutableArray array];
    for (id contact in contacts) {
        NSString *usrName = @"";
        @try {
            usrName = [contact valueForKey:@"m_nsUsrName"];
        } @catch (NSException *e) {}
        if (![[MiYouLiteManager sharedManager] isFriendHidden:usrName]) {
            [filtered addObject:contact];
        }
    }
    return filtered;
}
%end

#pragma mark - 密友 - 过滤会话列表

%hook MMNewSessionMgr
- (int)GetSessionCount {
    int count = %orig;
    if (![MiYouLiteManager sharedManager].hideModeEnabled) return count;
    if ([MiYouLiteManager sharedManager].isUnlocked) return count;
    // 减去隐藏的会话
    int hidden = (int)([MiYouLiteManager sharedManager].hiddenFriends.count +
                       [MiYouLiteManager sharedManager].hiddenRooms.count);
    return MAX(0, count - hidden);
}

- (id)GetSessionAtIndex:(int)arg1 {
    id session = %orig;
    if (!session) return nil;
    if (![MiYouLiteManager sharedManager].hideModeEnabled) return session;
    if ([MiYouLiteManager sharedManager].isUnlocked) return session;
    
    // 检查会话是否被隐藏
    NSString *sessionName = @"";
    @try {
        sessionName = [session valueForKey:@"m_nsUserName"];
    } @catch (NSException *e) {}
    
    if ([[MiYouLiteManager sharedManager] isFriendHidden:sessionName] ||
        [[MiYouLiteManager sharedManager] isRoomHidden:sessionName]) {
        // 跳过隐藏的会话，返回下一个
        return [self GetSessionAtIndex:arg1 + 1];
    }
    return session;
}
%end

#pragma mark - 密友 - 搜索框密码解锁

%hook UISearchBar
- (void)textDidChange:(id)arg1 {
    %orig;
    // 检查是否是在微信主界面的搜索框
    NSString *text = [self text];
    MiYouLiteManager *mgr = [MiYouLiteManager sharedManager];
    
    if (mgr.hideModeEnabled && mgr.password.length > 0) {
        if ([text isEqualToString:mgr.password]) {
            mgr.isUnlocked = YES;
            // 刷新界面
            [[NSNotificationCenter defaultCenter] postNotificationName:@"MiYouLiteUnlocked" object:nil];
            NSLog(@"[MiYouLite] 密码匹配，已解锁");
            // 延迟重置解锁状态（退出搜索后自动锁定）
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                mgr.isUnlocked = NO;
                [[NSNotificationCenter defaultCenter] postNotificationName:@"MiYouLiteUnlocked" object:nil];
            });
        }
    }
}
%end

#pragma mark - 构造函数

%ctor {
    NSLog(@"[MiYouLite] 插件已加载 - 版本 1.0.0");
    // 监听通知，刷新联系人列表
    [[NSNotificationCenter defaultCenter] addObserverForName:@"MiYouLiteUnlocked" object:nil queue:nil usingBlock:^(NSNotification *note) {
        // 强制刷新微信界面
        UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        if ([rootVC respondsToSelector:@selector(reloadData)]) {
            [rootVC performSelector:@selector(reloadData)];
        }
    }];
}