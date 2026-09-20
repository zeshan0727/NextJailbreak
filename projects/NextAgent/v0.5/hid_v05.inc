/*
 * Next Agent v0.5 RootHide HID extension.
 * Private IOHID symbols are resolved at runtime so the daemon stays portable
 * across the supported iOS 16 RootHide environment.
 */

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach_time.h>

typedef struct __IOHIDEvent *NAHIDEventRef;
typedef struct __IOHIDEventSystemClient *NAHIDSystemClientRef;
typedef int32_t NAIOReturn;
typedef uint32_t NAIOOptionBits;

enum {
    NA_HID_EVENT_DIGITIZER = 11,
    NA_DIGITIZER_RANGE = 0x00000001,
    NA_DIGITIZER_TOUCH = 0x00000002,
    NA_DIGITIZER_POSITION = 0x00000004,
    NA_DIGITIZER_TIP = 0x00000008,
    NA_DIGITIZER_IDENTITY = 0x00000010,
    NA_USAGE_PAGE_KEYBOARD = 0x07
};

static NAHIDEventRef (*na_create_digitizer_event)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t,
    uint32_t, uint32_t, double, double, double, double, double,
    Boolean, Boolean, NAIOOptionBits);

static NAHIDEventRef (*na_create_finger_event)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t, uint32_t, uint32_t,
    double, double, double, double, double, Boolean, Boolean, NAIOOptionBits);

static NAHIDEventRef (*na_create_keyboard_event)(
    CFAllocatorRef, uint64_t, uint16_t, uint16_t, Boolean, NAIOOptionBits);

static NAHIDSystemClientRef (*na_system_client_create)(CFAllocatorRef);
static NAIOReturn (*na_dispatch_event)(NAHIDSystemClientRef, NAHIDEventRef);
static void (*na_append_event)(NAHIDEventRef, NAHIDEventRef, NAIOOptionBits);
static void (*na_set_sender_id)(NAHIDEventRef, uint64_t);

static NAHIDSystemClientRef na_hid_client = NULL;
static bool na_hid_symbols_loaded = false;
static char na_hid_error[256] = {0};

static uint64_t na_hid_now(void) {
    static mach_timebase_info_data_t tb = {0};
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t now = mach_absolute_time();
    return (now * tb.numer) / tb.denom;
}

static bool na_hid_load(void) {
    if (na_hid_client) return true;
    if (na_hid_symbols_loaded && !na_hid_client) return false;
    na_hid_symbols_loaded = true;

    void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) handle = dlopen("/usr/lib/libIOKit.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!handle) {
        snprintf(na_hid_error, sizeof(na_hid_error), "Could not load IOKit");
        return false;
    }

    na_create_digitizer_event = dlsym(handle, "IOHIDEventCreateDigitizerEvent");
    na_create_finger_event = dlsym(handle, "IOHIDEventCreateDigitizerFingerEvent");
    na_create_keyboard_event = dlsym(handle, "IOHIDEventCreateKeyboardEvent");
    na_system_client_create = dlsym(handle, "IOHIDEventSystemClientCreate");
    na_dispatch_event = dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
    na_append_event = dlsym(handle, "IOHIDEventAppendEvent");
    na_set_sender_id = dlsym(handle, "IOHIDEventSetSenderID");

    if (!na_create_digitizer_event || !na_create_finger_event ||
        !na_create_keyboard_event || !na_system_client_create ||
        !na_dispatch_event || !na_append_event) {
        snprintf(na_hid_error, sizeof(na_hid_error), "Required IOHID symbols are unavailable");
        return false;
    }

    na_hid_client = na_system_client_create(kCFAllocatorDefault);
    if (!na_hid_client) {
        snprintf(na_hid_error, sizeof(na_hid_error), "IOHIDEventSystemClientCreate failed; verify HID entitlements");
        return false;
    }

    snprintf(na_hid_error, sizeof(na_hid_error), "ready");
    return true;
}

static void na_hid_prepare(NAHIDEventRef event) {
    if (event && na_set_sender_id) na_set_sender_id(event, 0x8000000817319375ULL);
}

static bool na_hid_dispatch(NAHIDEventRef event) {
    if (!event || !na_hid_load()) {
        if (event) CFRelease(event);
        return false;
    }
    na_hid_prepare(event);
    NAIOReturn result = na_dispatch_event(na_hid_client, event);
    CFRelease(event);
    return result == 0;
}

static NAHIDEventRef na_touch_event(double x, double y, bool down) {
    uint64_t now = na_hid_now();
    uint32_t mask = down
        ? (NA_DIGITIZER_RANGE | NA_DIGITIZER_TOUCH | NA_DIGITIZER_POSITION | NA_DIGITIZER_TIP | NA_DIGITIZER_IDENTITY)
        : (NA_DIGITIZER_RANGE | NA_DIGITIZER_POSITION | NA_DIGITIZER_IDENTITY);

    NAHIDEventRef finger = na_create_finger_event(
        kCFAllocatorDefault,
        now,
        0,
        1,
        mask,
        0,
        x, y, 0.0,
        down ? 1.0 : 0.0,
        0.0,
        true,
        down,
        0
    );
    if (!finger) return NULL;

    NAHIDEventRef parent = na_create_digitizer_event(
        kCFAllocatorDefault,
        now,
        NA_HID_EVENT_DIGITIZER,
        0,
        0,
        1,
        NA_DIGITIZER_RANGE | NA_DIGITIZER_TOUCH | NA_DIGITIZER_IDENTITY,
        0,
        0.0, 0.0, 0.0,
        0.0, 0.0,
        true,
        down,
        0
    );
    if (!parent) {
        CFRelease(finger);
        return NULL;
    }

    na_append_event(parent, finger, 0);
    CFRelease(finger);
    return parent;
}

static bool na_valid_unit(double v) {
    return v >= 0.0 && v <= 1.0;
}

static int na_parse_csv(const char *arg, double *values, int expected) {
    if (!arg || !*arg || expected <= 0) return 0;
    char *copy = strdup(arg);
    if (!copy) return 0;
    int count = 0;
    char *save = NULL;
    for (char *piece = strtok_r(copy, ",", &save); piece && count < expected; piece = strtok_r(NULL, ",", &save)) {
        char *end = NULL;
        errno = 0;
        double value = strtod(piece, &end);
        if (errno != 0 || !end || *end != 0) {
            free(copy);
            return 0;
        }
        values[count++] = value;
    }
    free(copy);
    return count == expected;
}

static bool na_touch_phase(double x, double y, bool down) {
    if (!na_valid_unit(x) || !na_valid_unit(y)) return false;
    return na_hid_dispatch(na_touch_event(x, y, down));
}

static char *action_hid_status(int *ok) {
    bool ready = na_hid_load();
    *ok = ready ? 1 : 0;
    char *error = json_escape(na_hid_error);
    char buffer[768];
    snprintf(buffer, sizeof(buffer),
             "{\"ready\":%s,\"touch\":%s,\"keyboard\":%s,\"detail\":\"%s\"}",
             ready ? "true" : "false",
             ready ? "true" : "false",
             ready ? "true" : "false",
             error ? error : "");
    free(error);
    return strdup(buffer);
}

static char *action_tap_v05(const char *arg, int *ok, bool double_tap) {
    double p[2];
    if (!na_parse_csv(arg, p, 2) || !na_valid_unit(p[0]) || !na_valid_unit(p[1])) {
        *ok = 0;
        return strdup("tap expects normalized x,y values from 0 to 1");
    }
    if (!na_hid_load()) {
        *ok = 0;
        return strdup(na_hid_error);
    }

    int count = double_tap ? 2 : 1;
    for (int i = 0; i < count; i++) {
        if (!na_touch_phase(p[0], p[1], true)) { *ok = 0; return strdup("touch-down dispatch failed"); }
        usleep(55 * 1000);
        if (!na_touch_phase(p[0], p[1], false)) { *ok = 0; return strdup("touch-up dispatch failed"); }
        if (i + 1 < count) usleep(110 * 1000);
    }
    *ok = 1;
    return strdup(double_tap ? "double tap dispatched" : "tap dispatched");
}

static char *action_long_press_v05(const char *arg, int *ok) {
    double p[3];
    if (!na_parse_csv(arg, p, 3) || !na_valid_unit(p[0]) || !na_valid_unit(p[1]) || p[2] < 0.2 || p[2] > 8.0) {
        *ok = 0;
        return strdup("long_press expects x,y,duration");
    }
    if (!na_hid_load()) { *ok = 0; return strdup(na_hid_error); }
    if (!na_touch_phase(p[0], p[1], true)) { *ok = 0; return strdup("touch-down dispatch failed"); }
    usleep((useconds_t)(p[2] * 1000000.0));
    if (!na_touch_phase(p[0], p[1], false)) { *ok = 0; return strdup("touch-up dispatch failed"); }
    *ok = 1;
    return strdup("long press dispatched");
}

static char *action_swipe_v05(const char *arg, int *ok) {
    double p[5];
    if (!na_parse_csv(arg, p, 5) ||
        !na_valid_unit(p[0]) || !na_valid_unit(p[1]) ||
        !na_valid_unit(p[2]) || !na_valid_unit(p[3]) ||
        p[4] < 0.1 || p[4] > 5.0) {
        *ok = 0;
        return strdup("swipe expects x1,y1,x2,y2,duration");
    }
    if (!na_hid_load()) { *ok = 0; return strdup(na_hid_error); }

    const int frames = 24;
    if (!na_touch_phase(p[0], p[1], true)) { *ok = 0; return strdup("swipe start failed"); }
    for (int i = 1; i <= frames; i++) {
        double t = (double)i / (double)frames;
        double x = p[0] + (p[2] - p[0]) * t;
        double y = p[1] + (p[3] - p[1]) * t;
        usleep((useconds_t)((p[4] / frames) * 1000000.0));
        if (!na_touch_phase(x, y, true)) { *ok = 0; return strdup("swipe move failed"); }
    }
    usleep(20 * 1000);
    if (!na_touch_phase(p[2], p[3], false)) { *ok = 0; return strdup("swipe end failed"); }
    *ok = 1;
    return strdup("swipe dispatched");
}

static bool na_key_event(uint16_t usage, bool down) {
    if (!na_hid_load()) return false;
    NAHIDEventRef event = na_create_keyboard_event(
        kCFAllocatorDefault,
        na_hid_now(),
        NA_USAGE_PAGE_KEYBOARD,
        usage,
        down,
        0
    );
    return na_hid_dispatch(event);
}

static bool na_press_usage(uint16_t usage) {
    if (!na_key_event(usage, true)) return false;
    usleep(35 * 1000);
    if (!na_key_event(usage, false)) return false;
    return true;
}

static int na_key_usage(const char *key) {
    if (!key) return -1;
    if (!strcmp(key, "enter") || !strcmp(key, "return")) return 0x28;
    if (!strcmp(key, "escape") || !strcmp(key, "esc")) return 0x29;
    if (!strcmp(key, "backspace") || !strcmp(key, "delete")) return 0x2A;
    if (!strcmp(key, "tab")) return 0x2B;
    if (!strcmp(key, "space")) return 0x2C;
    if (!strcmp(key, "right")) return 0x4F;
    if (!strcmp(key, "left")) return 0x50;
    if (!strcmp(key, "down")) return 0x51;
    if (!strcmp(key, "up")) return 0x52;
    return -1;
}

static char *action_key_v05(const char *arg, int *ok) {
    int usage = na_key_usage(arg);
    if (usage < 0) {
        *ok = 0;
        return strdup("unsupported key; use enter, backspace, tab, space, escape, up, down, left or right");
    }
    if (!na_press_usage((uint16_t)usage)) {
        *ok = 0;
        return strdup(na_hid_error[0] ? na_hid_error : "keyboard dispatch failed");
    }
    *ok = 1;
    return strdup("key dispatched");
}

static char *action_paste_v05(int *ok) {
    if (!na_hid_load()) {
        *ok = 0;
        return strdup(na_hid_error);
    }

    const uint16_t left_command = 0xE3;
    const uint16_t v_key = 0x19;

    if (!na_key_event(left_command, true)) { *ok = 0; return strdup("command key-down failed"); }
    usleep(30 * 1000);
    if (!na_key_event(v_key, true)) { na_key_event(left_command, false); *ok = 0; return strdup("V key-down failed"); }
    usleep(35 * 1000);
    na_key_event(v_key, false);
    usleep(20 * 1000);
    na_key_event(left_command, false);

    *ok = 1;
    return strdup("paste shortcut dispatched");
}

static char *action_packages_v05(int *ok) {
    char jbroot[4096] = {0};
    if (!detect_jbroot(jbroot)) {
        *ok = 0;
        return strdup("RootHide jbroot was not detected");
    }

    char status_path[8192];
    snprintf(status_path, sizeof(status_path), "%s/var/lib/dpkg/status", jbroot);
    FILE *file = fopen(status_path, "r");
    if (!file) {
        *ok = 0;
        return strdup(strerror(errno));
    }

    char *out = calloc(1, MAX_OUTPUT + 1);
    if (!out) {
        fclose(file);
        *ok = 0;
        return strdup("out of memory");
    }

    size_t used = 0;
    size_t count = 0;
    bool first = true;
    char package[512] = {0};
    char version[512] = {0};
    char line[4096];

    used += snprintf(out + used, MAX_OUTPUT - used, "{\"packages\":[");

    while (fgets(line, sizeof(line), file)) {
        if (!strncmp(line, "Package: ", 9)) {
            strlcpy(package, line + 9, sizeof(package));
            package[strcspn(package, "\r\n")] = 0;
        } else if (!strncmp(line, "Version: ", 9)) {
            strlcpy(version, line + 9, sizeof(version));
            version[strcspn(version, "\r\n")] = 0;
        } else if (line[0] == '\n' || line[0] == '\r') {
            if (package[0] && version[0]) {
                char *ep = json_escape(package);
                char *ev = json_escape(version);
                int n = snprintf(out + used, MAX_OUTPUT - used,
                                 "%s{\"package\":\"%s\",\"version\":\"%s\"}",
                                 first ? "" : ",", ep ? ep : "", ev ? ev : "");
                free(ep);
                free(ev);
                if (n < 0 || used + (size_t)n + 64 >= MAX_OUTPUT) break;
                used += (size_t)n;
                first = false;
                count++;
            }
            package[0] = 0;
            version[0] = 0;
        }
    }
    fclose(file);

    used += snprintf(out + used, MAX_OUTPUT - used, "],\"count\":%zu}", count);
    out[used] = 0;
    *ok = 1;
    return out;
}
