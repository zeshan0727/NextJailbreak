/*
 * Next Agent v0.7.3 internal progress channel.
 * Progress is written only to a fixed shared file and never to an arbitrary path.
 */

#include <notify.h>

static const char *NA_PROGRESS_PATH = "/var/mobile/Library/NextAgent/progress.json";
static const char *NA_PROGRESS_NOTIFY = "uk.zeshanbarvi.nextagent.progress.changed";

static bool na_progress_payload_safe(const char *arg) {
    if (!arg) return false;
    size_t n = strlen(arg);
    if (n == 0 || n > 8192) return false;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)arg[i];
        if (c == 0) return false;
    }
    return true;
}

static char *action_progress_v073(const char *arg, int *ok) {
    if (!na_progress_payload_safe(arg)) {
        *ok = 0;
        return strdup("progress payload must be UTF-8 JSON text up to 8 KiB");
    }

    if (!ensure_dir("/var/mobile/Library/NextAgent", 0700, 501, 501)) {
        *ok = 0;
        return strdup("could not create progress directory");
    }

    char tmp[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "%s.tmp.%d", NA_PROGRESS_PATH, getpid());

    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) {
        *ok = 0;
        return strdup(strerror(errno));
    }

    size_t len = strlen(arg);
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, arg + off, len - off);
        if (n > 0) {
            off += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        int e = errno;
        close(fd);
        unlink(tmp);
        *ok = 0;
        return strdup(strerror(e));
    }

    fsync(fd);
    fchown(fd, 501, 501);
    fchmod(fd, 0644);
    close(fd);

    if (rename(tmp, NA_PROGRESS_PATH) != 0) {
        int e = errno;
        unlink(tmp);
        *ok = 0;
        return strdup(strerror(e));
    }

    chown(NA_PROGRESS_PATH, 501, 501);
    chmod(NA_PROGRESS_PATH, 0644);
    notify_post(NA_PROGRESS_NOTIFY);

    *ok = 1;
    return strdup("progress updated");
}

static char *action_progress_clear_v073(int *ok) {
    const char *idle = "{\"state\":\"idle\",\"message\":\"\",\"progress\":0,\"return_to_app\":false}";
    return action_progress_v073(idle, ok);
}
