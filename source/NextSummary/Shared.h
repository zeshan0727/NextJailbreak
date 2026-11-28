#import <Foundation/Foundation.h>
extern NSString *const NSUChanged;
NSDictionary *NSUConfig(void);
BOOL NSUSave(NSDictionary *config);
NSURLSessionDataTask *NSUSummarize(NSDictionary *config, NSString *body, void (^done)(NSString *));
