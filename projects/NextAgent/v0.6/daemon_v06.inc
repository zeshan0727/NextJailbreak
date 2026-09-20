/*
 * Next Agent v0.6 combined production daemon extensions.
 * Includes global screenshot capture, safe package/service actions,
 * archive helpers, and read-only battery diagnostics.
 */

#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#include <mach/mach.h>
#include <dlfcn.h>

typedef uint32_t na_io_object_t;
typedef na_io_object_t na_io_iterator_t;
typedef na_io_object_t na_io_registry_entry_t;
typedef int32_t na_kern_return_t;
typedef uint32_t na_io_option_bits_t;

static bool na_is_safe_mobile_path(const char *raw) {
    if (!raw || raw[0] != '/') return false;
    if (strstr(raw, "\n") || strstr(raw, "\r") || strstr(raw, "\t")) return false;
    if (!strncmp(raw, "/var/mobile", 11) && (raw[11] == 0 || raw[11] == '/')) return true;
    if (!strncmp(raw, "/private/var/mobile", 19) && (raw[19] == 0 || raw[19] == '/')) return true;
    return false;
}

static bool na_safe_package_id(const char *p) {
    if (!p || !*p || strlen(p) > 200) return false;
    for (const unsigned char *c = (const unsigned char *)p; *c; c++) {
        if (!(isalnum(*c) || *c == '.' || *c == '+' || *c == '-')) return false;
    }
    static const char *blocked[] = {
        "firmware", "dpkg", "apt", "apt7", "essential", "bash", "coreutils",
        "launchctl", "roothide", "dopamine", "ellekit",
        "uk.zeshanbarvi.nextagentd.roothide"
    };
    for (size_t i = 0; i < sizeof(blocked)/sizeof(blocked[0]); i++) {
        if (!strcasecmp(p, blocked[i])) return false;
    }
    return true;
}

static bool na_safe_service_label(const char *label) {
    if (!label || !*label || strlen(label) > 240) return false;
    if (!strncmp(label, "com.apple.", 10) || !strncmp(label, "apple.", 6)) return false;
    for (const unsigned char *c = (const unsigned char *)label; *c; c++) {
        if (!(isalnum(*c) || *c == '.' || *c == '_' || *c == '-')) return false;
    }
    return true;
}

static char *na_shell_quote(const char *s) {
    if (!s) return strdup("''");
    size_t len = strlen(s);
    size_t cap = len * 5 + 3;
    char *out = malloc(cap);
    if (!out) return NULL;
    size_t j = 0;
    out[j++] = '\'';
    for (size_t i = 0; i < len; i++) {
        if (s[i] == '\'') {
            const char *rep = "'\\''";
            memcpy(out + j, rep, 4);
            j += 4;
        } else {
            out[j++] = s[i];
        }
    }
    out[j++] = '\'';
    out[j] = 0;
    return out;
}

static bool na_split_tab_pair(const char *arg, char **left, char **right) {
    if (!arg) return false;
    const char *tab = strchr(arg, '\t');
    if (!tab || tab == arg || tab[1] == 0) return false;
    size_t n = (size_t)(tab - arg);
    *left = strndup(arg, n);
    *right = strdup(tab + 1);
    if (!*left || !*right) {
        free(*left); free(*right);
        *left = NULL; *right = NULL;
        return false;
    }
    return true;
}

#pragma mark - Global screenshot

typedef CGImageRef (*na_sb_copy_screen_fn)(void);

static char *action_screenshot_v06(int *ok) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        *ok = 0;
        return strdup("SpringBoardServices could not be loaded");
    }

    na_sb_copy_screen_fn copyScreen = (na_sb_copy_screen_fn)dlsym(handle, "SBSCopyMainScreenImage");
    if (!copyScreen) copyScreen = (na_sb_copy_screen_fn)dlsym(handle, "_SBSCopyMainScreenImage");
    if (!copyScreen) {
        *ok = 0;
        return strdup("SBSCopyMainScreenImage is unavailable on this build");
    }

    CGImageRef image = copyScreen();
    if (!image) {
        *ok = 0;
        return strdup("Global screenshot capture returned no image");
    }

    char dir[4096], tokenPath[4096];
    token_locations(dir, tokenPath);
    mkdir(dir, 0700);
    chown(dir, 501, 501);

    char path[4096];
    snprintf(path, sizeof(path), "%s/last-screen.png", dir);

    CFURLRef url = CFURLCreateFromFileSystemRepresentation(
        kCFAllocatorDefault,
        (const UInt8 *)path,
        (CFIndex)strlen(path),
        false
    );
    if (!url) {
        CGImageRelease(image);
        *ok = 0;
        return strdup("Could not create screenshot output URL");
    }

    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
    CFRelease(url);
    if (!destination) {
        CGImageRelease(image);
        *ok = 0;
        return strdup("Could not create PNG encoder");
    }

    CGImageDestinationAddImage(destination, image, NULL);
    bool saved = CGImageDestinationFinalize(destination);
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    CFRelease(destination);
    CGImageRelease(image);

    if (!saved) {
        *ok = 0;
        return strdup("PNG screenshot encoding failed");
    }
    chmod(path, 0600);
    chown(path, 501, 501);

    char *escaped = json_escape(path);
    char out[1024];
    snprintf(out, sizeof(out),
             "{\"path\":\"%s\",\"width\":%zu,\"height\":%zu,\"format\":\"png\"}",
             escaped ? escaped : "", width, height);
    free(escaped);
    *ok = 1;
    return strdup(out);
}

#pragma mark - Package management

static char *action_package_install_v06(const char *arg, int *ok) {
    if (!na_is_safe_mobile_path(arg) || strlen(arg) < 5 || strcasecmp(arg + strlen(arg) - 4, ".deb")) {
        *ok = 0;
        return strdup("package_install accepts only an absolute .deb under /var/mobile");
    }
    struct stat st;
    if (lstat(arg, &st) != 0 || !S_ISREG(st.st_mode) || S_ISLNK(st.st_mode)) {
        *ok = 0;
        return strdup("package path must be an existing regular non-symlink file");
    }

    char jbroot[4096] = {0};
    if (!detect_jbroot(jbroot)) {
        *ok = 0;
        return strdup("RootHide jbroot not detected");
    }

    char dpkg[8192];
    snprintf(dpkg, sizeof(dpkg), "%s/usr/bin/dpkg", jbroot);
    if (access(dpkg, X_OK) != 0) {
        *ok = 0;
        return strdup("RootHide dpkg is unavailable");
    }

    char *qDpkg = na_shell_quote(dpkg);
    char *qPath = na_shell_quote(arg);
    if (!qDpkg || !qPath) {
        free(qDpkg); free(qPath);
        *ok = 0;
        return strdup("memory error");
    }

    char *cmd = malloc(strlen(qDpkg) + strlen(qPath) + 32);
    if (!cmd) {
        free(qDpkg); free(qPath);
        *ok = 0;
        return strdup("memory error");
    }
    sprintf(cmd, "%s -i -- %s 2>&1", qDpkg, qPath);
    free(qDpkg); free(qPath);

    int code = 0;
    char *out = run_fixed(cmd, &code);
    free(cmd);
    *ok = (code == 0);
    return out;
}

static char *action_package_remove_v06(const char *arg, int *ok) {
    if (!na_safe_package_id(arg)) {
        *ok = 0;
        return strdup("package identifier is invalid or protected from removal");
    }

    char jbroot[4096] = {0};
    if (!detect_jbroot(jbroot)) {
        *ok = 0;
        return strdup("RootHide jbroot not detected");
    }

    char dpkg[8192];
    snprintf(dpkg, sizeof(dpkg), "%s/usr/bin/dpkg", jbroot);
    char *qDpkg = na_shell_quote(dpkg);
    char *qPkg = na_shell_quote(arg);
    if (!qDpkg || !qPkg) {
        free(qDpkg); free(qPkg);
        *ok = 0;
        return strdup("memory error");
    }

    char *cmd = malloc(strlen(qDpkg) + strlen(qPkg) + 32);
    if (!cmd) {
        free(qDpkg); free(qPkg);
        *ok = 0;
        return strdup("memory error");
    }
    sprintf(cmd, "%s -r -- %s 2>&1", qDpkg, qPkg);
    free(qDpkg); free(qPkg);

    int code = 0;
    char *out = run_fixed(cmd, &code);
    free(cmd);
    *ok = (code == 0);
    return out;
}

#pragma mark - Archives

static char *action_archive_create_v06(const char *arg, int *ok) {
    char *source = NULL, *destination = NULL;
    if (!na_split_tab_pair(arg, &source, &destination) ||
        !na_is_safe_mobile_path(source) || !na_is_safe_mobile_path(destination) ||
        strlen(destination) < 8 || strcasecmp(destination + strlen(destination) - 7, ".tar.gz")) {
        free(source); free(destination);
        *ok = 0;
        return strdup("archive_create requires source and .tar.gz destination under /var/mobile");
    }

    char *qSource = na_shell_quote(source);
    char *qDestination = na_shell_quote(destination);
    free(source); free(destination);
    if (!qSource || !qDestination) {
        free(qSource); free(qDestination);
        *ok = 0;
        return strdup("memory error");
    }

    size_t n = strlen(qSource) + strlen(qDestination) + 256;
    char *cmd = malloc(n);
    snprintf(cmd, n,
             "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/var/jb/usr/bin; "
             "if command -v tar >/dev/null 2>&1; then tar -czf %s -- %s 2>&1; "
             "else echo 'tar not found'; exit 127; fi",
             qDestination, qSource);
    free(qSource); free(qDestination);

    int code = 0;
    char *out = run_fixed(cmd, &code);
    free(cmd);
    *ok = (code == 0);
    return out;
}

static char *action_archive_extract_v06(const char *arg, int *ok) {
    char *archive = NULL, *destination = NULL;
    if (!na_split_tab_pair(arg, &archive, &destination) ||
        !na_is_safe_mobile_path(archive) || !na_is_safe_mobile_path(destination) ||
        strlen(archive) < 8 || strcasecmp(archive + strlen(archive) - 7, ".tar.gz")) {
        free(archive); free(destination);
        *ok = 0;
        return strdup("archive_extract requires a .tar.gz and destination under /var/mobile");
    }

    mkdir(destination, 0755);
    char *qArchive = na_shell_quote(archive);
    char *qDestination = na_shell_quote(destination);
    free(archive); free(destination);
    if (!qArchive || !qDestination) {
        free(qArchive); free(qDestination);
        *ok = 0;
        return strdup("memory error");
    }

    size_t n = strlen(qArchive) + strlen(qDestination) + 256;
    char *cmd = malloc(n);
    snprintf(cmd, n,
             "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/var/jb/usr/bin; "
             "if command -v tar >/dev/null 2>&1; then tar -xzf %s -C %s 2>&1; "
             "else echo 'tar not found'; exit 127; fi",
             qArchive, qDestination);
    free(qArchive); free(qDestination);

    int code = 0;
    char *out = run_fixed(cmd, &code);
    free(cmd);
    *ok = (code == 0);
    return out;
}

#pragma mark - System and service control

static char *action_ldrestart_v06(int *ok) {
    int code = 0;
    char *out = run_fixed(
        "PATH=/usr/bin:/bin:/usr/sbin:/sbin:/var/jb/usr/bin; "
        "if command -v ldrestart >/dev/null 2>&1; then ldrestart 2>&1; "
        "else echo 'ldrestart not found'; exit 127; fi",
        &code
    );
    *ok = (code == 0);
    return out;
}

static char *action_userspace_reboot_v06(int *ok) {
    int code = 0;
    char *out = run_fixed("launchctl reboot userspace 2>&1", &code);
    *ok = (code == 0);
    return out;
}

static char *action_service_v06(const char *action, const char *label, int *ok) {
    if (!na_safe_service_label(label)) {
        *ok = 0;
        return strdup("Only non-Apple third-party launchd labels are allowed");
    }

    char *qLabel = na_shell_quote(label);
    if (!qLabel) {
        *ok = 0;
        return strdup("memory error");
    }

    size_t n = strlen(qLabel) + 320;
    char *cmd = malloc(n);
    if (!cmd) {
        free(qLabel);
        *ok = 0;
        return strdup("memory error");
    }

    if (!strcmp(action, "status")) {
        snprintf(cmd, n,
                 "launchctl print user/501/%s 2>&1 || launchctl print system/%s 2>&1",
                 label, label);
    } else if (!strcmp(action, "start")) {
        snprintf(cmd, n,
                 "launchctl kickstart user/501/%s 2>&1 || launchctl kickstart system/%s 2>&1",
                 label, label);
    } else if (!strcmp(action, "restart")) {
        snprintf(cmd, n,
                 "launchctl kickstart -k user/501/%s 2>&1 || launchctl kickstart -k system/%s 2>&1",
                 label, label);
    } else {
        snprintf(cmd, n,
                 "launchctl kill SIGTERM user/501/%s 2>&1 || launchctl kill SIGTERM system/%s 2>&1",
                 label, label);
    }
    free(qLabel);

    int code = 0;
    char *out = run_fixed(cmd, &code);
    free(cmd);
    *ok = (code == 0);
    return out;
}

#pragma mark - Battery diagnostics

typedef CFMutableDictionaryRef (*na_IOServiceMatching_fn)(const char *);
typedef na_kern_return_t (*na_IOServiceGetMatchingServices_fn)(mach_port_t, CFDictionaryRef, na_io_iterator_t *);
typedef na_io_object_t (*na_IOIteratorNext_fn)(na_io_iterator_t);
typedef na_kern_return_t (*na_IOObjectRelease_fn)(na_io_object_t);
typedef na_kern_return_t (*na_IORegistryEntryCreateCFProperties_fn)(na_io_registry_entry_t, CFMutableDictionaryRef *, CFAllocatorRef, na_io_option_bits_t);

static void *na_iokit_handle = NULL;
static na_IOServiceMatching_fn na_IOServiceMatching = NULL;
static na_IOServiceGetMatchingServices_fn na_IOServiceGetMatchingServices = NULL;
static na_IOIteratorNext_fn na_IOIteratorNext = NULL;
static na_IOObjectRelease_fn na_IOObjectRelease = NULL;
static na_IORegistryEntryCreateCFProperties_fn na_IORegistryEntryCreateCFProperties = NULL;

static bool na_battery_load_iokit(void) {
    if (na_iokit_handle && na_IOServiceMatching) return true;
    na_iokit_handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!na_iokit_handle) return false;

    na_IOServiceMatching = dlsym(na_iokit_handle, "IOServiceMatching");
    na_IOServiceGetMatchingServices = dlsym(na_iokit_handle, "IOServiceGetMatchingServices");
    na_IOIteratorNext = dlsym(na_iokit_handle, "IOIteratorNext");
    na_IOObjectRelease = dlsym(na_iokit_handle, "IOObjectRelease");
    na_IORegistryEntryCreateCFProperties = dlsym(na_iokit_handle, "IORegistryEntryCreateCFProperties");

    return na_IOServiceMatching && na_IOServiceGetMatchingServices &&
           na_IOIteratorNext && na_IOObjectRelease && na_IORegistryEntryCreateCFProperties;
}

static void na_json_append_cf_value(char *out, size_t cap, size_t *used, CFTypeRef value) {
    if (!value || *used + 16 >= cap) return;

    CFTypeID type = CFGetTypeID(value);
    if (type == CFNumberGetTypeID()) {
        double d = 0;
        CFNumberGetValue((CFNumberRef)value, kCFNumberDoubleType, &d);
        *used += snprintf(out + *used, cap - *used, "%.6g", d);
    } else if (type == CFBooleanGetTypeID()) {
        *used += snprintf(out + *used, cap - *used, "%s", CFBooleanGetValue((CFBooleanRef)value) ? "true" : "false");
    } else if (type == CFStringGetTypeID()) {
        char buf[4096] = {0};
        if (CFStringGetCString((CFStringRef)value, buf, sizeof(buf), kCFStringEncodingUTF8)) {
            char *e = json_escape(buf);
            *used += snprintf(out + *used, cap - *used, "\"%s\"", e ? e : "");
            free(e);
        } else {
            *used += snprintf(out + *used, cap - *used, "null");
        }
    } else if (type == CFArrayGetTypeID()) {
        *used += snprintf(out + *used, cap - *used, "[");
        CFIndex count = MIN(CFArrayGetCount((CFArrayRef)value), 32);
        for (CFIndex i = 0; i < count && *used + 64 < cap; i++) {
            if (i) *used += snprintf(out + *used, cap - *used, ",");
            na_json_append_cf_value(out, cap, used, CFArrayGetValueAtIndex((CFArrayRef)value, i));
        }
        *used += snprintf(out + *used, cap - *used, "]");
    } else {
        *used += snprintf(out + *used, cap - *used, "null");
    }
}

static char *action_battery_properties_v06(int *ok) {
    if (!na_battery_load_iokit()) {
        *ok = 0;
        return strdup("IOKit battery symbols are unavailable");
    }

    static const char *classes[] = {
        "AppleSmartBattery",
        "AppleEmbeddedBatteryManager",
        "AppleARMPMUCharger"
    };
    static const char *keys[] = {
        "CurrentCapacity", "MaxCapacity", "DesignCapacity", "CycleCount",
        "Voltage", "Amperage", "InstantAmperage", "Temperature",
        "BatteryInstalled", "IsCharging", "ExternalConnected", "FullyCharged",
        "AppleRawCurrentCapacity", "AppleRawMaxCapacity", "NominalChargeCapacity",
        "StateOfCharge", "TimeRemaining", "ChargingCurrent", "ChargingVoltage",
        "CellVoltage", "Qmax", "Flags", "AtCriticalLevel", "AtWarnLevel"
    };

    size_t cap = 131072;
    char *out = calloc(1, cap);
    if (!out) { *ok = 0; return strdup("memory error"); }
    size_t used = 0;
    used += snprintf(out + used, cap - used, "{\"source\":\"IOKit registry\",\"services\":[");

    bool firstService = true;
    int readable = 0;

    for (size_t ci = 0; ci < sizeof(classes)/sizeof(classes[0]); ci++) {
        CFMutableDictionaryRef matching = na_IOServiceMatching(classes[ci]);
        if (!matching) continue;

        na_io_iterator_t iterator = 0;
        if (na_IOServiceGetMatchingServices(MACH_PORT_NULL, matching, &iterator) != 0) continue;

        na_io_object_t service = 0;
        int serviceCount = 0;
        while ((service = na_IOIteratorNext(iterator)) != 0 && serviceCount < 8 && used + 4096 < cap) {
            serviceCount++;
            CFMutableDictionaryRef properties = NULL;
            if (na_IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == 0 && properties) {
                if (!firstService) used += snprintf(out + used, cap - used, ",");
                firstService = false;
                readable++;
                used += snprintf(out + used, cap - used, "{\"matched_class\":\"%s\",\"properties\":{", classes[ci]);

                bool firstKey = true;
                for (size_t ki = 0; ki < sizeof(keys)/sizeof(keys[0]); ki++) {
                    CFStringRef key = CFStringCreateWithCString(kCFAllocatorDefault, keys[ki], kCFStringEncodingUTF8);
                    CFTypeRef value = key ? CFDictionaryGetValue(properties, key) : NULL;
                    if (value) {
                        if (!firstKey) used += snprintf(out + used, cap - used, ",");
                        firstKey = false;
                        used += snprintf(out + used, cap - used, "\"%s\":", keys[ki]);
                        na_json_append_cf_value(out, cap, &used, value);
                    }
                    if (key) CFRelease(key);
                }
                used += snprintf(out + used, cap - used, "}}");
                CFRelease(properties);
            }
            na_IOObjectRelease(service);
        }
        na_IOObjectRelease(iterator);
    }

    used += snprintf(out + used, cap - used, "],\"readable_services\":%d}", readable);
    out[used] = 0;
    *ok = readable > 0;
    if (!*ok) {
        free(out);
        return strdup("No readable battery IOKit services were found");
    }
    return out;
}

static bool na_allowed_battery_plist(const char *path) {
    static const char *allowed[] = {
        "/var/db/Battery/BI/delta_nccp.plist",
        "/var/db/Battery/BI/delta_qmaxp.plist",
        "/var/db/Battery/BI/delta_wra.plist",
        "/var/root/Library/Preferences/com.apple.powerd.bdc.plist",
        "/var/root/Library/Preferences/com.apple.powerdatad.plist",
        "/var/root/Library/Preferences/com.apple.peakpowermanagerd.plist",
        "/var/mobile/Library/Preferences/com.apple.powerui.cec.plist"
    };
    for (size_t i = 0; i < sizeof(allowed)/sizeof(allowed[0]); i++) {
        if (!strcmp(path, allowed[i])) return true;
    }
    return false;
}

static char *na_redact_xml_lines(const char *xml) {
    if (!xml) return strdup("");
    size_t cap = strlen(xml) + 4096;
    char *out = calloc(1, cap);
    if (!out) return NULL;

    const char *cursor = xml;
    size_t used = 0;
    bool redactNext = false;

    while (*cursor) {
        const char *end = strchr(cursor, '\n');
        size_t len = end ? (size_t)(end - cursor + 1) : strlen(cursor);
        char line[16384];
        size_t copyLen = MIN(len, sizeof(line) - 1);
        memcpy(line, cursor, copyLen);
        line[copyLen] = 0;

        char lower[16384];
        for (size_t i = 0; i < copyLen && i + 1 < sizeof(lower); i++) lower[i] = (char)tolower((unsigned char)line[i]);
        lower[copyLen] = 0;

        if (strstr(lower, "<key>") &&
            (strstr(lower, "serial") || strstr(lower, "password") || strstr(lower, "token") ||
             strstr(lower, "secret") || strstr(lower, "credential") || strstr(lower, "privatekey") ||
             strstr(lower, "api_key") || strstr(lower, "apikey") || strstr(lower, "uniqueid") || strstr(lower, "udid"))) {
            redactNext = true;
            if (used + copyLen + 1 < cap) { memcpy(out + used, line, copyLen); used += copyLen; }
        } else if (redactNext && (strstr(lower, "<string>") || strstr(lower, "<data>") || strstr(lower, "<integer>") || strstr(lower, "<real>"))) {
            const char *replacement = "    <string>&lt;redacted&gt;</string>\n";
            size_t n = strlen(replacement);
            if (used + n + 1 < cap) { memcpy(out + used, replacement, n); used += n; }
            redactNext = false;
        } else {
            if (used + copyLen + 1 < cap) { memcpy(out + used, line, copyLen); used += copyLen; }
            if (strstr(lower, "</dict>") || strstr(lower, "</array>")) redactNext = false;
        }

        if (!end) break;
        cursor = end + 1;
    }
    out[used] = 0;
    return out;
}

static char *action_read_battery_plist_v06(const char *path, int *ok) {
    if (!na_allowed_battery_plist(path)) {
        *ok = 0;
        return strdup("Battery plist path is not allow-listed");
    }

    const char *actual = path;
    char physical[4096];
    if (!strncmp(path, "/var/", 5)) {
        snprintf(physical, sizeof(physical), "/private%s", path);
        actual = physical;
    }

    int fd = open(actual, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        *ok = 0;
        return strdup(strerror(errno));
    }

    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 0 || st.st_size > 1024 * 1024) {
        close(fd);
        *ok = 0;
        return strdup("Battery plist is not a regular file or exceeds 1 MiB");
    }

    size_t size = (size_t)st.st_size;
    UInt8 *bytes = malloc(size ? size : 1);
    if (!bytes) {
        close(fd);
        *ok = 0;
        return strdup("memory error");
    }

    size_t off = 0;
    while (off < size) {
        ssize_t r = read(fd, bytes + off, size - off);
        if (r < 0 && errno == EINTR) continue;
        if (r <= 0) break;
        off += (size_t)r;
    }
    close(fd);

    CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)off);
    free(bytes);
    if (!data) { *ok = 0; return strdup("Could not create plist data"); }

    CFErrorRef error = NULL;
    CFPropertyListFormat format = kCFPropertyListBinaryFormat_v1_0;
    CFPropertyListRef plist = CFPropertyListCreateWithData(kCFAllocatorDefault, data, kCFPropertyListImmutable, &format, &error);
    CFRelease(data);
    if (!plist) {
        if (error) CFRelease(error);
        *ok = 0;
        return strdup("Battery plist could not be decoded");
    }

    CFDataRef xmlData = CFPropertyListCreateData(kCFAllocatorDefault, plist, kCFPropertyListXMLFormat_v1_0, 0, &error);
    CFRelease(plist);
    if (!xmlData) {
        if (error) CFRelease(error);
        *ok = 0;
        return strdup("Battery plist XML conversion failed");
    }

    CFIndex xmlLen = CFDataGetLength(xmlData);
    char *xml = malloc((size_t)xmlLen + 1);
    memcpy(xml, CFDataGetBytePtr(xmlData), (size_t)xmlLen);
    xml[xmlLen] = 0;
    CFRelease(xmlData);

    char *redacted = na_redact_xml_lines(xml);
    free(xml);
    if (!redacted) { *ok = 0; return strdup("memory error"); }

    char *escapedPath = json_escape(path);
    char *escapedXML = json_escape(redacted);
    free(redacted);

    size_t cap = (escapedXML ? strlen(escapedXML) : 0) + 2048;
    char *out = malloc(cap);
    snprintf(out, cap,
             "{\"path\":\"%s\",\"format\":\"%s\",\"bytes_read\":%zu,\"contents_xml\":\"%s\"}",
             escapedPath ? escapedPath : "",
             format == kCFPropertyListBinaryFormat_v1_0 ? "binary" :
             format == kCFPropertyListXMLFormat_v1_0 ? "xml" : "openstep",
             off,
             escapedXML ? escapedXML : "");
    free(escapedPath); free(escapedXML);
    *ok = 1;
    return out;
}
