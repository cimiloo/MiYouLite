#import "DeptViewController.h"
#import "JJToast.h"

@implementation DeptViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 74;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 32)];
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(16, 4, 288, 20)];
    lab.text = [NSString stringWithFormat:@"%lu 人 · 点一下即可复制号码",
                (unsigned long)self.dept.members.count];
    lab.font = [UIFont systemFontOfSize:12];
    lab.textColor = [UIColor secondaryLabelColor];
    [header addSubview:lab];
    self.tableView.tableHeaderView = header;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.dept.members.count;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"pcell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                             reuseIdentifier:cid];

    JJPerson *p = self.dept.members[(NSUInteger)ip.row];

    NSString *name = p.name.length ? p.name : @"（未登记姓名）";
    if (p.title.length) name = [NSString stringWithFormat:@"%@   %@", name, p.title];
    cell.textLabel.text = name;
    cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
    cell.textLabel.numberOfLines = 1;

    NSMutableString *sub = [NSMutableString string];
    if (p.mobile.length) [sub appendFormat:@"手机 %@", p.mobile];
    if (p.office.length) {
        if (sub.length) [sub appendString:@"    "];
        [sub appendFormat:@"办公 %@", p.office];
    }
    if (p.room.length) {
        if (sub.length) [sub appendString:@"    "];
        [sub appendFormat:@"房间 %@", p.room];
    }
    if (sub.length == 0) sub = [NSMutableString stringWithString:@"未登记号码"];

    cell.detailTextLabel.text = sub;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.textColor = (p.mobile.length || p.office.length)
        ? [UIColor systemBlueColor] : [UIColor tertiaryLabelColor];
    cell.detailTextLabel.numberOfLines = 1;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    JJPerson *p = self.dept.members[(NSUInteger)ip.row];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];
    JJCopyPersonFrom(self, p, cell);
}

@end
