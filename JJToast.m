#import "JJToast.h"

void JJToast(NSString *msg) {
    UIWindow *win = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    if (w.isKeyWindow) { win = w; break; }
                }
            }
            if (win) break;
        }
    }
    if (!win) win = UIApplication.sharedApplication.keyWindow;
    if (!win) return;

    UILabel *label = [UILabel new];
    label.text = msg;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont boldSystemFontOfSize:13];
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
    label.layer.cornerRadius = 10;
    label.layer.masksToBounds = YES;
    CGSize max = CGSizeMake(win.bounds.size.width - 80, 200);
    CGSize size = [label sizeThatFits:max];
    label.frame = CGRectMake(0, 0, size.width + 28, size.height + 18);
    label.center = CGPointMake(win.bounds.size.width / 2, win.bounds.size.height * 0.78);
    label.alpha = 0;
    [win addSubview:label];
    [UIView animateWithDuration:0.18 animations:^{
        label.alpha = 1;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:1.0 options:0 animations:^{
            label.alpha = 0;
        } completion:^(BOOL done) {
            [label removeFromSuperview];
        }];
    }];
}

void JJCopyNumber(NSString *number) {
    if (number.length == 0) return;
    UIPasteboard.generalPasteboard.string = number;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
    JJToast([NSString stringWithFormat:@"已复制 %@", number]);
}

void JJCopyPersonFrom(UIViewController *vc, JJPerson *p, UIView *anchor) {
    NSString *mobile = p.mobile ?: @"";
    NSString *office = p.office ?: @"";
    if (mobile.length == 0 && office.length == 0) {
        JJToast(@"未登记号码");
        return;
    }
    if (mobile.length == 0 || office.length == 0) {
        JJCopyNumber(mobile.length ? mobile : office);
        return;
    }
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:p.name
                                                                  message:p.title
                                                           preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"复制手机  %@", mobile]
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) { JJCopyNumber(mobile); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"复制办公  %@", office]
                                             style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction *a) { JJCopyNumber(office); }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = anchor ?: vc.view;
    sheet.popoverPresentationController.sourceRect = anchor ? anchor.bounds
                                                            : CGRectMake(vc.view.bounds.size.width / 2,
                                                                         vc.view.bounds.size.height / 2, 1, 1);
    [vc presentViewController:sheet animated:YES completion:nil];
}
