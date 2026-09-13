#import <Foundation/Foundation.h>

// The Linux/Theos SDK used by CI can expose older Foundation headers even
// though the app targets iOS 16, where NSArray firstObject is available.
// Declaring the selector here keeps the CI compile aligned with the runtime.
@interface NSArray (NJTCompatFirstObject)
- (id)firstObject;
@end
