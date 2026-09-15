#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>
#import <spawn.h>
#import <mach-o/dyld.h>
#include <string.h>
extern char **environ;

static NSString *DataDir(void) { return @"/var/mobile/Library/LiveTouchWallpaper"; }
static NSString *PrefsPath(void) { return @"/var/mobile/Library/Preferences/com.nextjailbreak.livetouch.plist"; }

static BOOL LTIsDirectory(NSString *path) {
    BOOL isDir = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir;
}

static NSString *LTDirectoryFromLoadedImage(NSString *imagePath) {
    NSArray<NSString *> *markers = @[
        @"/Library/MobileSubstrate/DynamicLibraries/",
        @"/usr/lib/TweakInject/"
    ];
    for (NSString *marker in markers) {
        NSRange r = [imagePath rangeOfString:marker options:NSCaseInsensitiveSearch];
        if (r.location != NSNotFound) {
            NSString *prefix = [imagePath substringToIndex:r.location];
            NSString *dir = [prefix stringByAppendingString:[marker substringToIndex:marker.length - 1]];
            if (dir.length && LTIsDirectory(dir)) return dir;
        }
    }
    return nil;
}

static NSString *LTDiscoverTweakDir(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSString *> *rootlessCandidates = @[
        @"/var/jb/Library/MobileSubstrate/DynamicLibraries",
        @"/var/jb/usr/lib/TweakInject"
    ];
    for (NSString *candidate in rootlessCandidates) {
        if (LTIsDirectory(candidate)) return candidate;
    }

    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name) continue;
        NSString *image = [NSString stringWithUTF8String:name];
        NSString *dir = LTDirectoryFromLoadedImage(image);
        if (dir.length) return dir;
    }

    NSDirectoryEnumerator *en = [fm enumeratorAtURL:[NSURL fileURLWithPath:@"/private/preboot"]
                         includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                            options:(NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants)
                                       errorHandler:^BOOL(NSURL *url, NSError *error) { return YES; }];
    NSUInteger inspected = 0;
    for (NSURL *url in en) {
        if (++inspected > 12000) break;
        NSString *p = url.path;
        if ([p hasSuffix:@"/Library/MobileSubstrate/DynamicLibraries"] || [p hasSuffix:@"/usr/lib/TweakInject"]) {
            if (LTIsDirectory(p)) return p;
        }
    }

    NSString *rootful = @"/Library/MobileSubstrate/DynamicLibraries";
    if (LTIsDirectory(rootful) && access(rootful.fileSystemRepresentation, W_OK) == 0) return rootful;
    return nil;
}

static NSString *LTModeForTweakDir(NSString *dir) {
    return [dir hasPrefix:@"/Library/"] ? @"rootful" : @"rootless";
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
    NSString *bundle = BundleRoot();
    NSString *dir = LTDiscoverTweakDir();
    if (!dir.length) {
        fprintf(stderr, "Could not discover jailbreak tweak directory. /var/jb was unavailable and no rootless preboot tweak path was found. Refusing to write to the read-only rootful /Library path.\n");
        return 20;
    }
    printf("Detected %s tweak directory: %s\n", LTModeForTweakDir(dir).UTF8String, dir.UTF8String);
    if (!EnsureDir(dir, 0755, 0, 0)) return 2;
    BOOL a = CopyReplace([bundle stringByAppendingPathComponent:@"LiveTouchEngine.dylib"], [dir stringByAppendingPathComponent:@"LiveTouchEngine.dylib"], 0755, 0, 0);
    BOOL b = CopyReplace([bundle stringByAppendingPathComponent:@"LiveTouchEngine.plist"], [dir stringByAppendingPathComponent:@"LiveTouchEngine.plist"], 0644, 0, 0);
    if (!EnsureDir(DataDir(), 0755, 501, 501)) return 3;
    printf("Engine installed (%s).\n", LTModeForTweakDir(dir).UTF8String);
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
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSString *dir = LTDiscoverTweakDir();
    if (dir.length) {
        NSRange libRange = [dir rangeOfString:@"/Library/MobileSubstrate/DynamicLibraries"];
        NSRange injectRange = [dir rangeOfString:@"/usr/lib/TweakInject"];
        NSString *prefix = nil;
        if (libRange.location != NSNotFound) prefix = [dir substringToIndex:libRange.location];
        else if (injectRange.location != NSNotFound) prefix = [dir substringToIndex:injectRange.location];
        if (prefix.length) [paths addObject:[prefix stringByAppendingString:@"/usr/bin/killall"]];
    }
    [paths addObject:@"/var/jb/usr/bin/killall"];
    [paths addObject:@"/usr/bin/killall"];
    for (NSString *p in paths) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:p]) {
            pid_t pid; const char *argv[] = { p.fileSystemRepresentation, "-9", "SpringBoard", NULL };
            int rc = posix_spawn(&pid, p.fileSystemRepresentation, NULL, NULL, (char * const *)argv, environ);
            if (rc == 0) { printf("Respring requested.\n"); return 0; }
        }
    }
    fprintf(stderr, "killall not found. Respring from your jailbreak UI.\n"); return 8;
}

int LTEmbeddedRootHelperMain(int argc, char *argv[]) {
    @autoreleasepool {
        if (geteuid() != 0) { fprintf(stderr, "Embedded root helper must run as root. uid=%d euid=%d\n", getuid(), geteuid()); return 70; }
        if (argc < 3 || strcmp(argv[1], "--root-helper") != 0) { fprintf(stderr, "No embedded helper command.\n"); return 64; }
        NSString *cmd = [NSString stringWithUTF8String:argv[2]];
        if ([cmd isEqualToString:@"install-engine"]) return InstallEngine();
        if ([cmd isEqualToString:@"apply"] && argc >= 7) return Apply([NSString stringWithUTF8String:argv[3]], [NSString stringWithUTF8String:argv[4]], [NSString stringWithUTF8String:argv[5]], atoi(argv[6]) != 0);
        if ([cmd isEqualToString:@"respring"]) return Respring();
        if ([cmd isEqualToString:@"status"]) {
            NSString *dir = LTDiscoverTweakDir();
            NSString *dylib = dir.length ? [dir stringByAppendingPathComponent:@"LiveTouchEngine.dylib"] : nil;
            BOOL installed = dylib.length && [[NSFileManager defaultManager] fileExistsAtPath:dylib];
            NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:PrefsPath()];
            printf("Engine: %s | TweakDir: %s | Wallpaper: %s | Mode: %s\n", installed ? "installed" : "not installed", dir.UTF8String ?: "not found", [prefs[@"videoPath"] fileSystemRepresentation] ?: "not set", [prefs[@"trigger"] UTF8String] ?: "tap");
            return installed ? 0 : 1;
        }
        fprintf(stderr, "Unknown command.\n"); return 64;
    }
}
