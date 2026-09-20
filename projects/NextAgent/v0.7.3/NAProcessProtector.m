#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <libproc.h>
#import <signal.h>
#import <errno.h>
#import <unistd.h>
#import <string.h>
#import "NAProcessProtector.h"

extern int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffer_size);

static const NSUInteger NAFlagPreventSuspend = 1u << 0;
static const NSUInteger NAFlagPreventThrottleDownCPU = 1u << 1;
static const NSUInteger NAFlagAllowIdleSleep = 1u << 2;
static const NSUInteger NAFlagForegroundPriority = 1u << 3;

static const NSUInteger NAReasonBackgroundUI = 7;
static const NSUInteger NAReasonContinuous = 10005;

static const uint32_t NAMemoryStatusSetPriorityProperties = 2;
static const uint32_t NAMemoryStatusPriorityIsAssertion = 1;

typedef struct {
    int32_t priority;
    uint64_t user_data;
} NAMemoryStatusPriorityProperties;

static id gAssertion;
static pid_t gProtectedPID = 0;
static int gJetsamPriority = 0;
static BOOL gAssertionValid = NO;
static NSString *gLastDetail = @"Not protected";

static NSDictionary *NAFailure(NSString *code, NSString *message) {
    return @{
        @"success": @NO,
        @"error": @{
            @"code": code ?: @"unknown",
            @"message": message ?: @"Unknown error"
        }
    };
}

static char *NAJSONString(NSDictionary *dictionary, int *ok) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
    if (!data) {
        if (ok) *ok = 0;
        return strdup([[NSString stringWithFormat:@"JSON serialization failed: %@", error.localizedDescription ?: @"unknown"] UTF8String]);
    }
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (ok) *ok = [dictionary[@"success"] boolValue] ? 1 : 0;
    return strdup(string.UTF8String ?: "{}");
}

static BOOL NAProcessLooksLikeNextAgent(pid_t pid, NSString **detail) {
    if (pid <= 1 || kill(pid, 0) != 0) {
        if (detail) *detail = [NSString stringWithFormat:@"PID %d is not running", pid];
        return NO;
    }

    char pathbuf[PROC_PIDPATHINFO_MAXSIZE] = {0};
    int length = proc_pidpath(pid, pathbuf, sizeof(pathbuf));
    if (length <= 0) {
        if (detail) *detail = [NSString stringWithFormat:@"Could not resolve PID %d path (errno %d)", pid, errno];
        return NO;
    }

    NSString *path = [NSString stringWithUTF8String:pathbuf] ?: @"";
    BOOL match = [path containsString:@"/Next Agent.app/"] && [path hasSuffix:@"/Next Agent"];
    if (detail) *detail = path;
    return match;
}

static BOOL NAAssertionObjectValid(id assertion) {
    if (!assertion) return NO;
    SEL valid = NSSelectorFromString(@"valid");
    if ([assertion respondsToSelector:valid]) {
        return ((BOOL (*)(id, SEL))objc_msgSend)(assertion, valid);
    }
    return YES;
}

static void NAInvalidateAssertion(void) {
    if (gAssertion) {
        SEL invalidate = NSSelectorFromString(@"invalidate");
        if ([gAssertion respondsToSelector:invalidate]) {
            ((void (*)(id, SEL))objc_msgSend)(gAssertion, invalidate);
        }
    }
    gAssertion = nil;
    gAssertionValid = NO;
}

static id NACreateAssertion(pid_t pid, NSUInteger flags, NSUInteger reason) {
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices",
        RTLD_NOW | RTLD_GLOBAL
    );
    if (!handle) return nil;

    Class cls = NSClassFromString(@"BKSProcessAssertion");
    if (!cls) return nil;

    id object = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(alloc));
    if (!object) return nil;

    SEL six = NSSelectorFromString(@"initWithPID:flags:reason:name:withHandler:acquire:");
    if ([object respondsToSelector:six]) {
        typedef id (*Fn)(id, SEL, int, unsigned int, unsigned int, id, id, BOOL);
        return ((Fn)objc_msgSend)(
            object, six, pid, (unsigned int)flags, (unsigned int)reason,
            @"NextAgentDaemonActiveTurn", nil, YES
        );
    }

    SEL five = NSSelectorFromString(@"initWithPID:flags:reason:name:withHandler:");
    if ([object respondsToSelector:five]) {
        typedef id (*Fn)(id, SEL, int, unsigned int, unsigned int, id, id);
        id assertion = ((Fn)objc_msgSend)(
            object, five, pid, (unsigned int)flags, (unsigned int)reason,
            @"NextAgentDaemonActiveTurn", nil
        );
        SEL acquire = NSSelectorFromString(@"acquire");
        if (assertion && [assertion respondsToSelector:acquire]) {
            ((BOOL (*)(id, SEL))objc_msgSend)(assertion, acquire);
        }
        return assertion;
    }

    SEL four = NSSelectorFromString(@"initWithPID:flags:reason:name:");
    if ([object respondsToSelector:four]) {
        typedef id (*Fn)(id, SEL, int, unsigned int, unsigned int, id);
        id assertion = ((Fn)objc_msgSend)(
            object, four, pid, (unsigned int)flags, (unsigned int)reason,
            @"NextAgentDaemonActiveTurn"
        );
        SEL acquire = NSSelectorFromString(@"acquire");
        if (assertion && [assertion respondsToSelector:acquire]) {
            ((BOOL (*)(id, SEL))objc_msgSend)(assertion, acquire);
        }
        return assertion;
    }

    return nil;
}

static int NASetJetsamPriority(pid_t pid, int priority) {
    NAMemoryStatusPriorityProperties properties = {
        .priority = priority,
        .user_data = 0
    };
    errno = 0;
    int result = memorystatus_control(
        NAMemoryStatusSetPriorityProperties,
        pid,
        NAMemoryStatusPriorityIsAssertion,
        &properties,
        sizeof(properties)
    );
    return result;
}

static NSDictionary *NAStatusDictionary(void) {
    BOOL processAlive = gProtectedPID > 1 && kill(gProtectedPID, 0) == 0;
    return @{
        @"success": @YES,
        @"protected_pid": @(gProtectedPID),
        @"process_alive": @(processAlive),
        @"assertion_valid": @(gAssertionValid && NAAssertionObjectValid(gAssertion)),
        @"jetsam_priority": @(gJetsamPriority),
        @"detail": gLastDetail ?: @""
    };
}

char *NAProtectProcessJSON(pid_t pid, int *ok) {
    @autoreleasepool {
        NSString *pathDetail = nil;
        if (!NAProcessLooksLikeNextAgent(pid, &pathDetail)) {
            return NAJSONString(NAFailure(
                @"invalid_target",
                [NSString stringWithFormat:@"Refusing to protect PID %d: %@", pid, pathDetail ?: @"not Next Agent"]
            ), ok);
        }

        if (gProtectedPID == pid && gAssertion && NAAssertionObjectValid(gAssertion)) {
            gAssertionValid = YES;
            return NAJSONString(NAStatusDictionary(), ok);
        }

        if (gProtectedPID > 1 && gProtectedPID != pid) {
            NAInvalidateAssertion();
            NASetJetsamPriority(gProtectedPID, 0);
        }

        const NSUInteger flags =
            NAFlagPreventSuspend |
            NAFlagPreventThrottleDownCPU |
            NAFlagAllowIdleSleep |
            NAFlagForegroundPriority;

        id assertion = NACreateAssertion(pid, flags, NAReasonContinuous);
        if (!assertion || !NAAssertionObjectValid(assertion)) {
            if (assertion) {
                SEL invalidate = NSSelectorFromString(@"invalidate");
                if ([assertion respondsToSelector:invalidate]) {
                    ((void (*)(id, SEL))objc_msgSend)(assertion, invalidate);
                }
            }
            assertion = NACreateAssertion(pid, flags, NAReasonBackgroundUI);
        }

        BOOL assertionValid = assertion && NAAssertionObjectValid(assertion);

        // iOS 16 uses the x10 jetsam bands. Keep Next Agent above the normal
        // foreground band while an active turn is running.
        int priority = 190;
        int jetsamResult = NASetJetsamPriority(pid, priority);
        int jetsamError = errno;

        if (!assertionValid && jetsamResult != 0) {
            if (assertion) {
                SEL invalidate = NSSelectorFromString(@"invalidate");
                if ([assertion respondsToSelector:invalidate]) {
                    ((void (*)(id, SEL))objc_msgSend)(assertion, invalidate);
                }
            }
            return NAJSONString(NAFailure(
                @"protection_failed",
                [NSString stringWithFormat:@"Assertion invalid and jetsam protection failed (%d, errno %d)", jetsamResult, jetsamError]
            ), ok);
        }

        gAssertion = assertion;
        gProtectedPID = pid;
        gAssertionValid = assertionValid;
        gJetsamPriority = jetsamResult == 0 ? priority : 0;
        gLastDetail = [NSString stringWithFormat:
            @"%@; assertion=%@; jetsam_result=%d errno=%d",
            pathDetail ?: @"",
            assertionValid ? @"valid" : @"unavailable",
            jetsamResult,
            jetsamError
        ];

        return NAJSONString(NAStatusDictionary(), ok);
    }
}

char *NAUnprotectProcessJSON(pid_t pid, int *ok) {
    @autoreleasepool {
        if (pid > 1 && gProtectedPID > 1 && pid != gProtectedPID) {
            return NAJSONString(NAFailure(
                @"pid_mismatch",
                [NSString stringWithFormat:@"Protected PID is %d, not %d", gProtectedPID, pid]
            ), ok);
        }

        pid_t oldPID = gProtectedPID;
        NAInvalidateAssertion();

        int jetsamResult = 0;
        int jetsamError = 0;
        if (oldPID > 1) {
            jetsamResult = NASetJetsamPriority(oldPID, 0);
            jetsamError = errno;
        }

        gProtectedPID = 0;
        gJetsamPriority = 0;
        gLastDetail = [NSString stringWithFormat:
            @"Released protection for PID %d; jetsam_result=%d errno=%d",
            oldPID, jetsamResult, jetsamError
        ];

        return NAJSONString(@{
            @"success": @YES,
            @"released_pid": @(oldPID),
            @"jetsam_result": @(jetsamResult),
            @"jetsam_errno": @(jetsamError)
        }, ok);
    }
}

char *NAProtectionStatusJSON(int *ok) {
    @autoreleasepool {
        return NAJSONString(NAStatusDictionary(), ok);
    }
}
