#import "NABackgroundAssertion.h"
#import <dlfcn.h>
#import <objc/message.h>
#import <unistd.h>

static const NSUInteger NAFlagPreventSuspend = 1u << 0;
static const NSUInteger NAFlagPreventThrottleDownCPU = 1u << 1;
static const NSUInteger NAFlagAllowIdleSleep = 1u << 2;
static const NSUInteger NAFlagWantsForegroundResourcePriority = 1u << 3;

static const NSUInteger NAReasonBackgroundUI = 7;
static const NSUInteger NAReasonContinuous = 10005;

@interface NABackgroundAssertionController ()
@property (nonatomic, strong, nullable) id assertion;
@property (nonatomic, readwrite, getter=isActive) BOOL active;
@property (nonatomic, readwrite, getter=isValid) BOOL valid;
@property (nonatomic, readwrite) NSString *status;
@end

@implementation NABackgroundAssertionController

+ (instancetype)sharedController {
    static NABackgroundAssertionController *controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        controller = [NABackgroundAssertionController new];
        controller.status = @"Not started";
    });
    return controller;
}

- (BOOL)start {
    @synchronized (self) {
        if (self.assertion && [self assertionIsValid:self.assertion]) {
            self.active = YES;
            self.valid = YES;
            self.status = @"Assertion active";
            return YES;
        }

        [self stop];

        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices",
            RTLD_NOW | RTLD_GLOBAL
        );
        if (!handle) {
            self.status = @"AssertionServices unavailable";
            return NO;
        }

        Class cls = NSClassFromString(@"BKSProcessAssertion");
        if (!cls) {
            self.status = @"BKSProcessAssertion class unavailable";
            return NO;
        }

        const NSUInteger flags =
            NAFlagPreventSuspend |
            NAFlagPreventThrottleDownCPU |
            NAFlagAllowIdleSleep |
            NAFlagWantsForegroundResourcePriority;

        id assertion = [self createAssertionWithClass:cls flags:flags reason:NAReasonContinuous];
        if (!assertion || ![self assertionIsValid:assertion]) {
            if (assertion && [assertion respondsToSelector:NSSelectorFromString(@"invalidate")]) {
                ((void (*)(id, SEL))objc_msgSend)(assertion, NSSelectorFromString(@"invalidate"));
            }
            assertion = [self createAssertionWithClass:cls flags:flags reason:NAReasonBackgroundUI];
        }

        self.assertion = assertion;
        self.active = assertion != nil;
        self.valid = assertion != nil && [self assertionIsValid:assertion];
        self.status = self.valid
            ? @"Pinned with AssertionServices"
            : (assertion ? @"Assertion created but not valid" : @"Could not create assertion");

        if (!self.valid) {
            [self stop];
            return NO;
        }
        return YES;
    }
}

- (id)createAssertionWithClass:(Class)cls flags:(NSUInteger)flags reason:(NSUInteger)reason {
    id object = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(alloc));
    if (!object) return nil;

    SEL six = NSSelectorFromString(@"initWithPID:flags:reason:name:withHandler:acquire:");
    if ([object respondsToSelector:six]) {
        typedef id (*Fn)(id, SEL, int, unsigned int, unsigned int, id, id, BOOL);
        return ((Fn)objc_msgSend)(
            object,
            six,
            getpid(),
            (unsigned int)flags,
            (unsigned int)reason,
            @"NextAgentActiveTurn",
            nil,
            YES
        );
    }

    SEL five = NSSelectorFromString(@"initWithPID:flags:reason:name:withHandler:");
    if ([object respondsToSelector:five]) {
        typedef id (*Fn)(id, SEL, int, unsigned int, unsigned int, id, id);
        id assertion = ((Fn)objc_msgSend)(
            object,
            five,
            getpid(),
            (unsigned int)flags,
            (unsigned int)reason,
            @"NextAgentActiveTurn",
            nil
        );
        [self acquireIfAvailable:assertion];
        return assertion;
    }

    SEL four = NSSelectorFromString(@"initWithPID:flags:reason:name:");
    if ([object respondsToSelector:four]) {
        typedef id (*Fn)(id, SEL, int, unsigned int, unsigned int, id);
        id assertion = ((Fn)objc_msgSend)(
            object,
            four,
            getpid(),
            (unsigned int)flags,
            (unsigned int)reason,
            @"NextAgentActiveTurn"
        );
        [self acquireIfAvailable:assertion];
        return assertion;
    }

    return nil;
}

- (void)acquireIfAvailable:(id)assertion {
    if (!assertion) return;
    SEL acquire = NSSelectorFromString(@"acquire");
    if ([assertion respondsToSelector:acquire]) {
        ((BOOL (*)(id, SEL))objc_msgSend)(assertion, acquire);
    }
}

- (BOOL)assertionIsValid:(id)assertion {
    if (!assertion) return NO;
    SEL valid = NSSelectorFromString(@"valid");
    if ([assertion respondsToSelector:valid]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(assertion, valid);
    }
    // Older variants do not expose -valid publicly. If creation succeeded,
    // keep the assertion rather than discarding it.
    return YES;
}

- (void)stop {
    @synchronized (self) {
        id assertion = self.assertion;
        if (assertion) {
            SEL invalidate = NSSelectorFromString(@"invalidate");
            if ([assertion respondsToSelector:invalidate]) {
                ((void (*)(id, SEL))objc_msgSend)(assertion, invalidate);
            }
        }
        self.assertion = nil;
        self.active = NO;
        self.valid = NO;
        self.status = @"Inactive";
    }
}

@end
