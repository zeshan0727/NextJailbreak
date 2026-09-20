#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import "NABatteryDiagnostics.h"

typedef mach_port_t na_io_object_t;
typedef na_io_object_t na_io_service_t;
typedef na_io_object_t na_io_iterator_t;

static const NSUInteger NAMaxPlistBytes = 1024 * 1024;
static const NSUInteger NAMaxServices = 16;

static CFMutableDictionaryRef (*p_IOServiceMatching)(const char *);
static kern_return_t (*p_IOServiceGetMatchingServices)(mach_port_t, CFDictionaryRef, na_io_iterator_t *);
static na_io_object_t (*p_IOIteratorNext)(na_io_iterator_t);
static kern_return_t (*p_IORegistryEntryGetRegistryEntryID)(na_io_service_t, uint64_t *);
static kern_return_t (*p_IORegistryEntryGetName)(na_io_service_t, char *);
static kern_return_t (*p_IORegistryEntryCreateCFProperties)(na_io_service_t, CFMutableDictionaryRef *, CFAllocatorRef, uint32_t);
static kern_return_t (*p_IOObjectRelease)(na_io_object_t);

static BOOL NALoadIOKit(void) {
    static dispatch_once_t onceToken;
    static BOOL loaded = NO;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) handle = dlopen("/usr/lib/libIOKit.dylib", RTLD_LAZY | RTLD_LOCAL);
        if (!handle) return;

        p_IOServiceMatching = dlsym(handle, "IOServiceMatching");
        p_IOServiceGetMatchingServices = dlsym(handle, "IOServiceGetMatchingServices");
        p_IOIteratorNext = dlsym(handle, "IOIteratorNext");
        p_IORegistryEntryGetRegistryEntryID = dlsym(handle, "IORegistryEntryGetRegistryEntryID");
        p_IORegistryEntryGetName = dlsym(handle, "IORegistryEntryGetName");
        p_IORegistryEntryCreateCFProperties = dlsym(handle, "IORegistryEntryCreateCFProperties");
        p_IOObjectRelease = dlsym(handle, "IOObjectRelease");

        loaded = p_IOServiceMatching &&
                 p_IOServiceGetMatchingServices &&
                 p_IOIteratorNext &&
                 p_IORegistryEntryGetRegistryEntryID &&
                 p_IORegistryEntryGetName &&
                 p_IORegistryEntryCreateCFProperties &&
                 p_IOObjectRelease;
    });
    return loaded;
}

static NSDictionary *NAFailure(NSString *code, NSString *message) {
    return @{
        @"success": @NO,
        @"error": @{
            @"code": code ?: @"unknown",
            @"message": message ?: @"Unknown error"
        }
    };
}

static NSString *NATimestamp(void) {
    return [[[NSISO8601DateFormatter alloc] init] stringFromDate:[NSDate date]];
}

static BOOL NASensitiveKey(NSString *key) {
    NSString *lower = key.lowercaseString;
    NSArray<NSString *> *blocked = @[
        @"serial", @"password", @"passwd", @"token", @"secret",
        @"credential", @"privatekey", @"private_key", @"apikey",
        @"api_key", @"uniqueid", @"unique_id", @"udid"
    ];
    for (NSString *fragment in blocked) {
        if ([lower containsString:fragment]) return YES;
    }
    return NO;
}

static id NAJSONValue(id value, NSUInteger depth) {
    if (!value) return [NSNull null];
    if (depth > 12) return @"<maximum nesting depth reached>";

    if ([value isKindOfClass:[NSString class]]) {
        NSString *string = value;
        if (string.length > 8192) {
            return [[string substringToIndex:8192] stringByAppendingString:@"<truncated>"];
        }
        return string;
    }

    if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *number = value;
        if (![NSJSONSerialization isValidJSONObject:@[number]]) return number.description;
        return number;
    }

    if ([value isKindOfClass:[NSNull class]]) return value;

    if ([value isKindOfClass:[NSDate class]]) {
        return [[[NSISO8601DateFormatter alloc] init] stringFromDate:value];
    }

    if ([value isKindOfClass:[NSData class]]) {
        return @{
            @"type": @"data",
            @"byte_count": @([(NSData *)value length]),
            @"contents_omitted": @YES
        };
    }

    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *result = [NSMutableArray array];
        NSArray *array = value;
        NSUInteger count = MIN(array.count, (NSUInteger)512);
        for (NSUInteger index = 0; index < count; index++) {
            [result addObject:NAJSONValue(array[index], depth + 1)];
        }
        if (array.count > count) [result addObject:@"<remaining items omitted>"];
        return result;
    }

    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        NSDictionary *dictionary = value;
        NSUInteger count = 0;
        for (id rawKey in dictionary) {
            if (++count > 1024) {
                result[@"__truncated__"] = @YES;
                break;
            }
            NSString *key = [rawKey isKindOfClass:[NSString class]] ? rawKey : [rawKey description];
            result[key] = NASensitiveKey(key)
                ? @"<redacted>"
                : NAJSONValue(dictionary[rawKey], depth + 1);
        }
        return result;
    }

    return @"<unsupported value type>";
}

static char *NAJSONString(NSDictionary *dictionary, int *ok) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionary options:NSJSONWritingPrettyPrinted error:&error];
    if (!data) {
        if (ok) *ok = 0;
        return strdup([[NSString stringWithFormat:@"JSON serialization failed: %@", error.localizedDescription ?: @"unknown"] UTF8String]);
    }
    NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (ok) *ok = [dictionary[@"success"] boolValue] ? 1 : 0;
    return strdup(string.UTF8String ?: "{}");
}

static NSDictionary *NAReadBatteryProperties(void) {
    if (!NALoadIOKit()) {
        return NAFailure(@"iokit_unavailable", @"Could not resolve the required IOKit battery APIs.");
    }

    NSArray<NSString *> *classes = @[
        @"AppleSmartBattery",
        @"AppleEmbeddedBatteryManager",
        @"AppleARMPMUCharger"
    ];

    NSMutableArray *services = [NSMutableArray array];
    NSMutableArray *diagnostics = [NSMutableArray array];
    NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
    BOOL serviceLimitReached = NO;

    for (NSString *serviceClass in classes) {
        if (services.count >= NAMaxServices) {
            serviceLimitReached = YES;
            break;
        }

        CFMutableDictionaryRef matching = p_IOServiceMatching(serviceClass.UTF8String);
        if (!matching) {
            [diagnostics addObject:@{
                @"service_class": serviceClass,
                @"error": @"Could not create matching dictionary."
            }];
            continue;
        }

        na_io_iterator_t iterator = MACH_PORT_NULL;
        kern_return_t status = p_IOServiceGetMatchingServices(MACH_PORT_NULL, matching, &iterator);
        if (status != KERN_SUCCESS) {
            [diagnostics addObject:@{
                @"service_class": serviceClass,
                @"iokit_status": @(status)
            }];
            continue;
        }

        na_io_service_t service = MACH_PORT_NULL;
        NSUInteger matchedCount = 0;

        while ((service = p_IOIteratorNext(iterator)) != MACH_PORT_NULL) {
            matchedCount++;
            if (services.count >= NAMaxServices) {
                serviceLimitReached = YES;
                p_IOObjectRelease(service);
                break;
            }

            uint64_t entryID = 0;
            BOOL hasEntryID = p_IORegistryEntryGetRegistryEntryID(service, &entryID) == KERN_SUCCESS;
            if (hasEntryID && [seen containsObject:@(entryID)]) {
                p_IOObjectRelease(service);
                continue;
            }
            if (hasEntryID) [seen addObject:@(entryID)];

            char registryName[128] = {0};
            p_IORegistryEntryGetName(service, registryName);

            CFMutableDictionaryRef rawProperties = NULL;
            status = p_IORegistryEntryCreateCFProperties(service, &rawProperties, kCFAllocatorDefault, 0);

            NSMutableDictionary *entry = [@{
                @"matched_class": serviceClass,
                @"registry_name": [NSString stringWithUTF8String:registryName] ?: @"",
                @"iokit_status": @(status)
            } mutableCopy];

            if (status == KERN_SUCCESS && rawProperties) {
                NSDictionary *properties = CFBridgingRelease(rawProperties);
                entry[@"properties"] = NAJSONValue(properties, 0);
            } else {
                if (rawProperties) CFRelease(rawProperties);
                entry[@"error"] = @"Could not read properties for this service.";
            }

            [services addObject:entry];
            p_IOObjectRelease(service);
        }

        p_IOObjectRelease(iterator);
        [diagnostics addObject:@{
            @"service_class": serviceClass,
            @"matched_count": @(matchedCount)
        }];
    }

    BOOL hasReadableProperties = NO;
    for (NSDictionary *service in services) {
        if (service[@"properties"]) {
            hasReadableProperties = YES;
            break;
        }
    }

    if (!hasReadableProperties) {
        NSMutableDictionary *failure = [NAFailure(
            @"battery_properties_unavailable",
            @"No readable battery service was found. Check the device's IOKit service names and the helper's access permissions."
        ) mutableCopy];
        failure[@"services"] = services;
        failure[@"diagnostics"] = diagnostics;
        return failure;
    }

    return @{
        @"success": @YES,
        @"source": @"IOKit registry",
        @"captured_at_utc": NATimestamp(),
        @"services": services,
        @"diagnostics": diagnostics,
        @"service_limit_reached": @(serviceLimitReached)
    };
}

static NSArray<NSString *> *NAAllowedPlistPaths(void) {
    return @[
        @"/var/db/Battery/BI/delta_nccp.plist",
        @"/var/db/Battery/BI/delta_qmaxp.plist",
        @"/var/db/Battery/BI/delta_wra.plist",
        @"/var/root/Library/Preferences/com.apple.powerd.bdc.plist",
        @"/var/root/Library/Preferences/com.apple.powerdatad.plist",
        @"/var/root/Library/Preferences/com.apple.peakpowermanagerd.plist",
        @"/var/mobile/Library/Preferences/com.apple.powerui.cec.plist"
    ];
}

static int NAOpenPlistReadOnly(NSString *logicalPath) {
    NSString *physicalPath = [@"/private" stringByAppendingString:logicalPath];
    NSArray<NSString *> *parts = [physicalPath componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *components = [NSMutableArray array];
    for (NSString *part in parts) {
        if (part.length > 0) [components addObject:part];
    }

    int current = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (current < 0) return -1;

    for (NSUInteger index = 0; index < components.count; index++) {
        BOOL finalComponent = index == components.count - 1;
        int flags = O_RDONLY | O_CLOEXEC | O_NOFOLLOW;
        if (!finalComponent) flags |= O_DIRECTORY;
        else flags |= O_NONBLOCK;

        int next = openat(current, components[index].fileSystemRepresentation, flags);
        int savedError = errno;
        close(current);

        if (next < 0) {
            errno = savedError;
            return -1;
        }
        current = next;
    }

    return current;
}

static NSDictionary *NAReadBatteryPlist(NSString *path) {
    if (![NAAllowedPlistPaths() containsObject:path]) {
        return NAFailure(
            @"path_not_allowed",
            @"This tool reads only the explicitly allowlisted battery property lists."
        );
    }

    int file = NAOpenPlistReadOnly(path);
    if (file < 0) {
        int code = errno;
        return NAFailure(
            @"open_failed",
            [NSString stringWithFormat:@"Could not open file: %s (%d).", strerror(code), code]
        );
    }

    struct stat info;
    if (fstat(file, &info) != 0) {
        close(file);
        return NAFailure(@"stat_failed", @"Could not inspect the file.");
    }
    if (!S_ISREG(info.st_mode)) {
        close(file);
        return NAFailure(@"not_regular_file", @"Path is not a regular file.");
    }
    if (info.st_size < 0 || (uint64_t)info.st_size > NAMaxPlistBytes) {
        close(file);
        return NAFailure(@"file_too_large", @"File exceeds the 1 MiB limit.");
    }

    NSMutableData *data = [NSMutableData data];
    unsigned char buffer[8192];

    while (YES) {
        ssize_t count = read(file, buffer, sizeof(buffer));
        if (count == 0) break;
        if (count < 0) {
            if (errno == EINTR) continue;
            close(file);
            return NAFailure(@"read_failed", @"Could not read the file.");
        }
        if (data.length + (NSUInteger)count > NAMaxPlistBytes) {
            close(file);
            return NAFailure(@"file_too_large", @"File grew beyond the 1 MiB limit while being read.");
        }
        [data appendBytes:buffer length:(NSUInteger)count];
    }
    close(file);

    NSError *error = nil;
    NSPropertyListFormat format = NSPropertyListBinaryFormat_v1_0;
    id plist = [NSPropertyListSerialization
        propertyListWithData:data
        options:NSPropertyListImmutable
        format:&format
        error:&error];

    if (!plist) {
        return NAFailure(@"invalid_plist", @"The file could not be decoded as a property list.");
    }

    NSString *formatName = @"unknown";
    switch (format) {
        case NSPropertyListBinaryFormat_v1_0: formatName = @"binary"; break;
        case NSPropertyListXMLFormat_v1_0: formatName = @"xml"; break;
        case NSPropertyListOpenStepFormat: formatName = @"openstep"; break;
    }

    return @{
        @"success": @YES,
        @"source": @"filesystem",
        @"path": path,
        @"format": formatName,
        @"bytes_read": @(data.length),
        @"captured_at_utc": NATimestamp(),
        @"contents": NAJSONValue(plist, 0)
    };
}

char *NABatteryPropertiesJSON(int *ok) {
    @autoreleasepool {
        return NAJSONString(NAReadBatteryProperties(), ok);
    }
}

char *NAReadBatteryPlistJSON(const char *path, int *ok) {
    @autoreleasepool {
        if (!path) {
            return NAJSONString(NAFailure(@"invalid_arguments", @"path must be provided."), ok);
        }
        NSString *value = [NSString stringWithUTF8String:path];
        if (!value) {
            return NAJSONString(NAFailure(@"invalid_arguments", @"path must be UTF-8."), ok);
        }
        return NAJSONString(NAReadBatteryPlist(value), ok);
    }
}
