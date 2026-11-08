#import "InstalledApps.h"
#import <objc/runtime.h>
#import <objc/message.h>
static id _Nullable getObj(id _Nullable obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id,SEL))objc_msgSend)(obj,sel);
}
@implementation InstalledApps
+ (NSArray<NSDictionary<NSString *,NSString *> *> *)installedApplications {
    Class c=NSClassFromString(@"LSApplicationWorkspace");
    id w=getObj(c,NSSelectorFromString(@"defaultWorkspace"));
    id a=getObj(w,NSSelectorFromString(@"allApplications"));
    if (![a isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out=[NSMutableArray array];
    for (id p in (NSArray *)a) {
        id identifier=getObj(p,NSSelectorFromString(@"applicationIdentifier"));
        if (![identifier isKindOfClass:[NSString class]] || ![identifier length]) continue;
        id label=getObj(p,NSSelectorFromString(@"localizedName"));
        id version=getObj(p,NSSelectorFromString(@"shortVersionString"));
        id url=getObj(p,NSSelectorFromString(@"bundleURL"));
        [out addObject:@{
            @"bundleID":identifier,
            @"name":[label isKindOfClass:[NSString class]] ? label : identifier,
            @"version":[version isKindOfClass:[NSString class]] ? version : @"Unknown",
            @"path":[url isKindOfClass:[NSURL class]] ? [url path] : @"Not exposed"
        }];
    }
    return out;
}
@end
