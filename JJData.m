#import "JJData.h"

@implementation JJPerson
@end

@implementation JJDept
- (instancetype)init {
    if (self = [super init]) _members = [NSMutableArray array];
    return self;
}
@end

@implementation JJGroup
- (instancetype)init {
    if (self = [super init]) _depts = [NSMutableArray array];
    return self;
}
@end

static NSArray<JJGroup *> *gGroups = nil;
static NSString *gUpdated = @"";

@implementation JJData

+ (void)loadIfNeeded {
    if (gGroups) return;
    gGroups = @[];
    NSString *path = [[NSBundle mainBundle] pathForResource:@"contacts" ofType:@"json"];
    if (!path) return;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return;
    NSError *err = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![root isKindOfClass:[NSDictionary class]]) return;

    gUpdated = root[@"updated"] ?: @"";
    NSMutableArray *groups = [NSMutableArray array];
    for (NSDictionary *gd in root[@"groups"]) {
        JJGroup *g = [JJGroup new];
        g.name = gd[@"name"] ?: @"";
        for (NSDictionary *dd in gd[@"depts"]) {
            JJDept *d = [JJDept new];
            d.name = dd[@"name"] ?: @"";
            for (NSDictionary *md in dd[@"members"]) {
                JJPerson *p = [JJPerson new];
                p.title = md[@"title"] ?: @"";
                p.name = md[@"name"] ?: @"";
                p.office = md[@"office"] ?: @"";
                p.mobile = md[@"mobile"] ?: @"";
                p.room = md[@"room"] ?: @"";
                p.dept = d.name;
                if (p.name.length == 0 && p.mobile.length == 0 && p.office.length == 0) continue;
                [d.members addObject:p];
            }
            if (d.members.count) [g.depts addObject:d];
        }
        if (g.depts.count) [groups addObject:g];
    }
    gGroups = groups;
}

+ (NSArray<JJGroup *> *)groups {
    [self loadIfNeeded];
    return gGroups;
}

+ (NSString *)updated {
    [self loadIfNeeded];
    return gUpdated;
}

+ (NSInteger)count {
    [self loadIfNeeded];
    NSInteger c = 0;
    for (JJGroup *g in gGroups)
        for (JJDept *d in g.depts) c += d.members.count;
    return c;
}

@end
