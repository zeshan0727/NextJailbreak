#!/usr/bin/env python3
"""1.0.21: clean Notify Island runtime; faster Open without motion bubbles."""
from pathlib import Path
p=Path(__file__).with_name("NotificationIsland.xm")
s=p.read_text()
def rep(a,b):
    global s
    if a not in s: raise SystemExit("1.0.21 missing anchor: "+a[:140])
    s=s.replace(a,b,1)
rep("static BOOL NANTestMode = NO;","static BOOL NANTestMode = NO;\nstatic BOOL NANOpeningApplication=NO;")
a=s.index('- (void)openTapped {')
b=s.index('\n- (void)dismissTapped {',a)
s=s[:a]+r'''- (void)openTapped {
    if (NANTestMode) { NANTestMode=NO; NANRemoveIsland(); return; }
    if (NANOpeningApplication || NANIsUILocked() || NANIslandView!=self || !self.bundleID.length) return;
    NSString *bundle=[self.bundleID copy];
    NANOpeningApplication=YES;
    // Close the custom overlay first, retaining native notification history.
    NANRemoveIsland();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.05*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        if (NANIsUILocked() || !NANBool(@"NotificationIslandEnabled",YES)) {
            NANOpeningApplication=NO;
            return;
        }
        // Keep potentially blocking LaunchServices IPC away from the UI thread.
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
            @try {
                Class cls=NSClassFromString(@"LSApplicationWorkspace");
                SEL shared=NSSelectorFromString(@"defaultWorkspace");
                id workspace=(cls && [cls respondsToSelector:shared])?((id(*)(id,SEL))objc_msgSend)(cls,shared):nil;
                SEL selector=NSSelectorFromString(@"openApplicationWithBundleID:");
                if ([workspace respondsToSelector:selector]) ((BOOL(*)(id,SEL,id))objc_msgSend)(workspace,selector,bundle);
            } @catch (__unused NSException *exception) {}
            dispatch_async(dispatch_get_main_queue(), ^{ NANOpeningApplication=NO; });
        });
    });
}
'''+s[b:]
rep('1.0.19 Banner Lifecycle loaded','1.0.21 Clean Island loaded')
# Fail preparation if any Motion Bubbles symbols leaked into the runtime.
for marker in ("NANFloatingManager","NANFloatingWindow","NotificationIslandFloatingIcons","CMMotionManager","bubbleTapped:"):
    if marker in s: raise SystemExit("Unexpected floating icon code: "+marker)
p.write_text(s)
print("Prepared Notify Island 1.0.21 Clean Island.")
