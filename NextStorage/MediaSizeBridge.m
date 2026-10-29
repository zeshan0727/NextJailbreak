#import "MediaSizeBridge.h"

// iOS 16 exposes the Photos resource file-size metadata through KVC, but not
// as a public SDK property. Isolate it in ObjC so missing fields return nil
// instead of causing an uncaught NSUnknownKeyException in Swift.
NSNumber * _Nullable NextPhotoResourceBytes(PHAssetResource *resource) {
    @try {
        id raw = [resource valueForKey:@"fileSize"];
        if ([raw isKindOfClass:[NSNumber class]]) {
            long long bytes = [(NSNumber *)raw longLongValue];
            if (bytes > 0) return @(bytes);
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return nil;
}
