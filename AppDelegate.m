#import "AppDelegate.h"
#import "MainViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];

    MainViewController *root = [MainViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:root];

    UIColor *red = [UIColor colorWithRed:0.61 green:0.106 blue:0.133 alpha:1.0];
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *ap = [UINavigationBarAppearance new];
        [ap configureWithOpaqueBackground];
        ap.backgroundColor = red;
        ap.titleTextAttributes = @{NSForegroundColorAttributeName : UIColor.whiteColor};
        nav.navigationBar.standardAppearance = ap;
        nav.navigationBar.scrollEdgeAppearance = ap;
        nav.navigationBar.compactAppearance = ap;
    }
    nav.navigationBar.tintColor = UIColor.whiteColor;
    nav.navigationBar.barStyle = UIBarStyleBlack;   // 状态栏白字
    nav.navigationBar.translucent = NO;

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
