#import <Foundation/Foundation.h>

@interface JJPerson : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *office;
@property (nonatomic, copy) NSString *mobile;
@property (nonatomic, copy) NSString *room;
@property (nonatomic, copy) NSString *dept;
@end

@interface JJDept : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<JJPerson *> *members;
@end

@interface JJGroup : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<JJDept *> *depts;
@end

@interface JJData : NSObject
+ (NSArray<JJGroup *> *)groups;
+ (NSString *)updated;
+ (NSInteger)count;
@end
