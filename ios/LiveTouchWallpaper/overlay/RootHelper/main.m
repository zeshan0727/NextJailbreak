#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <unistd.h>
#import <spawn.h>
#include <string.h>

static NSString *DataDir(void) { return @"/var/mobile/Library/LiveTouchWallpaper"; }
static NSString *PrefsPath(void) { return @"/var/mobile/Library/Preferences/com.nextjailbreak.livetouch.plist"; }

static BOOL IsDir(NSString *p) {
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] && d;
}

static NSString *DiscoverJBRoot(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *parents = @[@"/private/var/containers/Bundle/Application", @"/var/containers/Bundle/Application"];
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    for (NSString *parent in parents) {
        NSArray<NSString *> *items = [fm contentsOfDirectoryAtPath:parent error:nil];
        for (NSString *name in items ?: @[]) {
            if (![name hasPrefix:@".jbroot-"]) continue;
            NSString *candidate = [parent stringByAppendingPathComponent:name];
            if (![fm fileExistsAtPath:[candidate stringByAppendingPathComponent:@"usr/lib/libroothide.dylib"]]) continue;
            NSString *substrate = [candidate stringByAppendingPathComponent:@"Library/MobileSubstrate/DynamicLibraries"];
            NSString *inject = [candidate stringByAppendingPathComponent:@"usr/lib/TweakInject"];
            if (!IsDir(substrate) && !IsDir(inject)) continue;
            NSDictionary *attrs = [fm attributesOfItemAtPath:candidate error:nil];
            [matches addObject:@{ @"path":candidate, @"date":attrs[NSFileModificationDate] ?: [NSDate distantPast] }];
        }
        if (matches.count) break;
    }
    if (!matches.count) return nil;
    [matches sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [b[@"date"] compare:a[@"date"]]; }];
    return matches.firstObject[@"path"];
}

static NSString *JBPath(NSString *logical) {
    NSString *root = DiscoverJBRoot();
    if (!root.length) return nil;
    NSString *relative = [logical hasPrefix:@"/"] ? [logical substringFromIndex:1] : logical;
    return relative.length ? [root stringByAppendingPathComponent:relative] : root;
}

static NSString *TweakDir(void) {
    for (NSString *logical in @[@"/Library/MobileSubstrate/DynamicLibraries", @"/usr/lib/TweakInject"]) {
        NSString *p = JBPath(logical);
        if (p.length && IsDir(p)) return p;
    }
    return nil;
}

static BOOL EnsureDir(NSString *path, mode_t mode, uid_t uid, gid_t gid) {
    NSError *e = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&e];
    if (e) { fprintf(stderr, "mkdir %s failed: %s\n", path.UTF8String, e.localizedDescription.UTF8String); return NO; }
    chmod(path.fileSystemRepresentation, mode); chown(path.fileSystemRepresentation, uid, gid); return YES;
}

static NSString *BundleRoot(void) {
    NSString *exe = [NSString stringWithUTF8String:getenv("LIVETOUCH_BUNDLE") ?: ""];
    if (exe.length && [[NSFileManager defaultManager] fileExistsAtPath:exe]) return exe;
    NSString *argv0 = [NSProcessInfo processInfo].arguments.firstObject;
    return [argv0 stringByDeletingLastPathComponent];
}

static BOOL CopyReplace(NSString *src, NSString *dst, mode_t mode, uid_t uid, gid_t gid) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm fileExistsAtPath:src]) { fprintf(stderr, "Missing source: %s\n", src.UTF8String); return NO; }
    [fm removeItemAtPath:dst error:nil];
    NSError *e = nil;
    if (![fm copyItemAtPath:src toPath:dst error:&e]) { fprintf(stderr, "copy failed: %s\n", e.localizedDescription.UTF8String); return NO; }
    chmod(dst.fileSystemRepresentation, mode); chown(dst.fileSystemRepresentation, uid, gid); return YES;
}

static int InstallEngine(void) {
    NSString *dir = TweakDir();
    NSString *root = DiscoverJBRoot();
    if (!dir.length) {
        fprintf(stderr, "RootHide tweak directory not found. RootHide jbroot scan=%s\n", root.UTF8String ?: "unresolved");
        return 20;
    }
    NSString *bundle = BundleRoot();
    printf("RootHide jbroot: %s\n", root.UTF8String);
    printf("RootHide tweak directory: %s\n", dir.UTF8String);
    if (!EnsureDir(dir, 0755, 0, 0)) return 2;
    BOOL a = CopyReplace([bundle stringByAppendingPathComponent:@"LiveTouchEngine.dylib"], [dir stringByAppendingPathComponent:@"LiveTouchEngine.dylib"], 0755, 0, 0);
    BOOL b = CopyReplace([bundle stringByAppendingPathComponent:@"LiveTouchEngine.plist"], [dir stringByAppendingPathComponent:@"LiveTouchEngine.plist"], 0644, 0, 0);
    if (!EnsureDir(DataDir(), 0755, 501, 501)) return 3;
    printf("Engine installed for RootHide.\n");
    return (a && b) ? 0 : 4;
}

static int Apply(NSString *video, NSString *trigger, NSString *gravity, BOOL mute) {
    int r = InstallEngine(); if (r != 0) return r;
    if (!EnsureDir(DataDir(), 0755, 501, 501)) return 5;
    NSString *ext = video.pathExtension.length ? video.pathExtension.lowercaseString : @"mov";
    NSString *dst = [DataDir() stringByAppendingPathComponent:[NSString stringWithFormat:@"current.%@", ext]];
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *old in [fm contentsOfDirectoryAtPath:DataDir() error:nil]) if ([old hasPrefix:@"current."]) [fm removeItemAtPath:[DataDir() stringByAppendingPathComponent:old] error:nil];
    if (!CopyReplace(video, dst, 0644, 501, 501)) return 6;
    NSDictionary *prefs = @{ @"videoPath": dst, @"trigger": trigger ?: @"tap", @"gravity": gravity ?: @"fill", @"mute": @(mute), @"enabled": @YES };
    NSError *e = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:prefs format:NSPropertyListBinaryFormat_v1_0 options:0 error:&e];
    if (!data || ![data writeToFile:PrefsPath() options:NSDataWritingAtomic error:&e]) { fprintf(stderr, "prefs failed: %s\n", e.localizedDescription.UTF8String); return 7; }
    chmod(PrefsPath().fileSystemRepresentation, 0644); chown(PrefsPath().fileSystemRepresentation, 501, 501);
    printf("Wallpaper applied: %s\n", dst.UTF8String);
    return 0;
}

static int Respring(void) {
    NSString *killall = JBPath(@"/usr/bin/killall");
    if (!killall.length || ![[NSFileManager defaultManager] isExecutableFileAtPath:killall]) {
        fprintf(stderr, "RootHide killall not found in detected jbroot.\n");
        return 8;
    }
    pid_t pid;
    const char *argv[] = { killall.fileSystemRepresentation, "-9", "SpringBoard", NULL };
    int rc = posix_spawn(&pid, killall.fileSystemRepresentation, NULL, NULL, (char * const *)argv, NULL);
    if (rc == 0) { printf("RootHide respring requested.\n"); return 0; }
    fprintf(stderr, "killall spawn failed: %d (%s)\n", rc, strerror(rc));
    return rc;
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (geteuid() != 0) { fprintf(stderr, "LiveTouchRootHelper must run as root. uid=%d\n", geteuid()); return 70; }
        if (argc < 2) { fprintf(stderr, "No command.\n"); return 64; }
        NSString *cmd = [NSString stringWithUTF8String:argv[1]];
        if ([cmd isEqualToString:@"install-engine"]) return InstallEngine();
        if ([cmd isEqualToString:@"apply"] && argc >= 6) return Apply([NSString stringWithUTF8String:argv[2]], [NSString stringWithUTF8String:argv[3]], [NSString stringWithUTF8String:argv[4]], atoi(argv[5]) != 0);
        if ([cmd isEqualToString:@"respring"]) return Respring();
        if ([cmd isEqualToString:@"status"]) {
            NSString *dir = TweakDir();
            NSString *dylib = dir.length ? [dir stringByAppendingPathComponent:@"LiveTouchEngine.dylib"] : nil;
            BOOL installed = dylib.length && [[NSFileManager defaultManager] fileExistsAtPath:dylib];
            NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PrefsPath()];
            printf("Engine: %s | RootHide jbroot: %s | TweakDir: %s | Wallpaper: %s | Mode: %s\n",
                   installed ? "installed" : "not installed", DiscoverJBRoot().UTF8String ?: "unresolved", dir.UTF8String ?: "not found",
                   [prefs[@"videoPath"] fileSystemRepresentation] ?: "not set", [prefs[@"trigger"] UTF8String] ?: "tap");
            return installed ? 0 : 1;
        }
        fprintf(stderr, "Unknown command.\n"); return 64;
    }
}
