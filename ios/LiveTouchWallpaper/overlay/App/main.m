#import <UIKit/UIKit.h>
#import "LTAppDelegate.h"
#import "LTRootHelperEmbedded.h"
#include <string.h>

int main(int argc, char * argv[]) {
    @autoreleasepool {
        if (argc >= 2 && strcmp(argv[1], "--root-helper") == 0) {
            return LTEmbeddedRootHelperMain(argc, argv);
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([LTAppDelegate class]));
    }
}
