/*
 * Next Agent v0.7.4 SpringBoard overlay bridge.
 * Uses fixed paths + Darwin notifications only; no arbitrary command execution.
 */

#include <notify.h>
#include <time.h>

static const char *NA074_SCREEN_REQUEST_PATH = "/var/mobile/Library/NextAgent/screen.request.json";
static const char *NA074_SCREEN_RESPONSE_PATH = "/var/mobile/Library/NextAgent/screen.response.json";
static const char *NA074_OVERLAY_STATUS_PATH = "/var/mobile/Library/NextAgent/overlay.status.json";
static const char *NA074_SCREEN_REQUEST_NOTIFY = "uk.zeshanbarvi.nextagent.screen.capture.request";

static char *na074_read_small_file(const char *path, size_t limit) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return NULL;

    char *out = calloc(1, limit + 1);
    if (!out) {
        close(fd);
        return NULL;
    }

    size_t used = 0;
    while (used < limit) {
        ssize_t n = read(fd, out + used, limit - used);
        if (n > 0) {
            used += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        break;
    }
    close(fd);
    out[used] = 0;
    return out;
}

static bool na074_write_atomic(const char *path, const char *text, mode_t mode, uid_t uid, gid_t gid) {
    if (!path || !text) return false;

    char tmp[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "%s.tmp.%d", path, getpid());

    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, mode);
    if (fd < 0) return false;

    size_t len = strlen(text);
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, text + off, len - off);
        if (n > 0) {
            off += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        close(fd);
        unlink(tmp);
        return false;
    }

    fsync(fd);
    fchown(fd, uid, gid);
    fchmod(fd, mode);
    close(fd);

    if (rename(tmp, path) != 0) {
        unlink(tmp);
        return false;
    }
    chown(path, uid, gid);
    chmod(path, mode);
    return true;
}

static char *action_overlay_status_v074(int *ok) {
    char *text = na074_read_small_file(NA074_OVERLAY_STATUS_PATH, 16384);
    if (!text || !*text) {
        free(text);
        *ok = 0;
        return strdup("SpringBoard overlay status file is unavailable. The overlay is probably not injected; respring after installing the RootHide package.");
    }

    *ok = strstr(text, "\"loaded\":true") != NULL;
    return text;
}

static char *action_overlay_wait_pin_v074(const char *arg, int *ok) {
    if (!arg || !*arg) {
        *ok = 0;
        return strdup("missing PID");
    }

    long value = strtol(arg, NULL, 10);
    if (value <= 1 || value > INT_MAX) {
        *ok = 0;
        return strdup("invalid PID");
    }

    char pidNeedle[96];
    snprintf(pidNeedle, sizeof(pidNeedle), "\"protected_pid\":%ld", value);

    char *last = NULL;
    for (int attempt = 0; attempt < 40; attempt++) {
        free(last);
        last = na074_read_small_file(NA074_OVERLAY_STATUS_PATH, 16384);

        if (last &&
            strstr(last, "\"loaded\":true") &&
            strstr(last, pidNeedle) &&
            strstr(last, "\"assertion_valid\":true")) {
            *ok = 1;
            return last;
        }

        usleep(50 * 1000);
    }

    *ok = 0;
    if (last) return last;
    return strdup("Timed out waiting for SpringBoard to pin Next Agent. Overlay status was unavailable.");
}

static char *action_screen_capture_v074(int *ok) {
    if (!ensure_dir("/var/mobile/Library/NextAgent", 0700, 501, 501)) {
        *ok = 0;
        return strdup("could not prepare Next Agent shared directory");
    }
    if (!ensure_dir("/var/mobile/Library/NextAgent/Captures", 0700, 501, 501)) {
        *ok = 0;
        return strdup("could not prepare capture directory");
    }

    static unsigned long counter = 0;
    counter++;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);

    char requestID[160];
    snprintf(
        requestID, sizeof(requestID),
        "%lld-%09ld-%d-%lu",
        (long long)ts.tv_sec,
        ts.tv_nsec,
        getpid(),
        counter
    );

    char request[512];
    snprintf(
        request, sizeof(request),
        "{\"request_id\":\"%s\",\"requested_at\":%lld}",
        requestID,
        (long long)ts.tv_sec
    );

    unlink(NA074_SCREEN_RESPONSE_PATH);
    if (!na074_write_atomic(NA074_SCREEN_REQUEST_PATH, request, 0644, 501, 501)) {
        *ok = 0;
        return strdup("could not write screen capture request");
    }

    notify_post(NA074_SCREEN_REQUEST_NOTIFY);

    char idNeedle[256];
    snprintf(idNeedle, sizeof(idNeedle), "\"request_id\":\"%s\"", requestID);

    char *response = NULL;
    for (int attempt = 0; attempt < 120; attempt++) {
        free(response);
        response = na074_read_small_file(NA074_SCREEN_RESPONSE_PATH, 32768);

        if (response && strstr(response, idNeedle)) {
            if (strstr(response, "\"success\":true")) {
                *ok = 1;
                return response;
            }

            *ok = 0;
            return response;
        }

        usleep(50 * 1000);
    }

    free(response);
    *ok = 0;
    return strdup("Timed out waiting for SpringBoard real-screen capture. Check overlay injection/status and respring.");
}
