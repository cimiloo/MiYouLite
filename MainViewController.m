#import "MainViewController.h"
#import "DeptViewController.h"
#import "JJData.h"
#import "JJToast.h"

@interface MainViewController () <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray<JJGroup *> *groups;
@property (nonatomic, strong) NSMutableArray<JJPerson *> *filtered;
@property (nonatomic, strong) UISearchController *searchController;
@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"纪检监察通讯录";
    self.groups = [JJData groups];
    self.filtered = [NSMutableArray array];

    self.tableView.rowHeight = 54;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];

    // 表头：总数 + 更新日期
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 34)];
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(16, 6, 288, 22)];
    lab.text = [NSString stringWithFormat:@"共 %ld 条 · 更新 %@", (long)[JJData count], [JJData updated]];
    lab.font = [UIFont systemFontOfSize:12];
    lab.textColor = [UIColor secondaryLabelColor];
    [header addSubview:lab];
    self.tableView.tableHeaderView = header;

    self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.searchController.searchResultsUpdater = self;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.searchBar.placeholder = @"搜索姓名 / 号码 / 部门";
    self.navigationItem.searchController = self.searchController;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
}

#pragma mark - 数据源

- (BOOL)isSearching {
    return self.searchController.isActive && self.searchController.searchBar.text.length > 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return [self isSearching] ? 1 : (NSInteger)self.groups.count;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)section {
    if ([self isSearching]) return (NSInteger)self.filtered.count;
    return (NSInteger)self.groups[(NSUInteger)section].depts.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)section {
    if ([self isSearching])
        return [NSString stringWithFormat:@"搜索结果  %ld", (long)self.filtered.count];
    JJGroup *g = self.groups[(NSUInteger)section];
    NSInteger n = 0;
    for (JJDept *d in g.depts) n += (NSInteger)d.members.count;
    return [NSString stringWithFormat:@"%@   %ld", g.name, (long)n];
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"cell";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:cid];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                             reuseIdentifier:cid];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if ([self isSearching]) {
        JJPerson *p = self.filtered[(NSUInteger)ip.row];
        NSString *main = p.name.length ? p.name : @"（未登记姓名）";
        if (p.title.length) main = [NSString stringWithFormat:@"%@  %@", main, p.title];
        cell.textLabel.text = main;
        cell.textLabel.font = [UIFont boldSystemFontOfSize:16];
        NSString *num = p.mobile.length ? p.mobile : p.office;
        cell.detailTextLabel.text = num.length ? num : @"无号码";
        cell.detailTextLabel.textColor = num.length ? [UIColor systemBlueColor]
                                                    : [UIColor tertiaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:14];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        JJDept *d = self.groups[(NSUInteger)ip.section].depts[(NSUInteger)ip.row];
        cell.textLabel.text = d.name;
        cell.textLabel.font = [UIFont systemFontOfSize:16];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu 人", (unsigned long)d.members.count];
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];

    if ([self isSearching]) {
        JJPerson *p = self.filtered[(NSUInteger)ip.row];
        JJCopyPersonFrom(self, p, cell);
        return;
    }
    JJDept *d = self.groups[(NSUInteger)ip.section].depts[(NSUInteger)ip.row];
    DeptViewController *vc = [DeptViewController new];
    vc.dept = d;
    vc.title = d.name;
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - 搜索

- (void)updateSearchResultsForSearchController:(UISearchController *)sc {
    [self.filtered removeAllObjects];
    NSString *q = sc.searchBar.text.lowercaseString;
    if (q.length == 0) {
        [self.tableView reloadData];
        return;
    }
    for (JJGroup *g in self.groups) {
        for (JJDept *d in g.depts) {
            for (JJPerson *p in d.members) {
                NSString *hay = [NSString stringWithFormat:@"%@ %@ %@ %@ %@ %@",
                                 p.name, p.title, p.mobile, p.office, p.room, d.name].lowercaseString;
                if ([hay rangeOfString:q].location != NSNotFound) [self.filtered addObject:p];
            }
        }
    }
    [self.tableView reloadData];
}

@end
