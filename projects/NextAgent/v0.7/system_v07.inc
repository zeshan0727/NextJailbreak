/*
 * Next Agent v0.7 system/file/package extension.
 * Included after hid_v05.inc, so it can reuse authenticated daemon helpers
 * and the HID client while keeping all mutating entry points allow-listed.
 */

#include <sys/time.h>
#include <limits.h>

static char *na_run_argv_capture(const char *path, char *const argv[], int *exit_code) {
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        *exit_code = errno;
        return strdup(strerror(errno));
    }

    pid_t pid = fork();
    if (pid < 0) {
        int e = errno;
        close(pipefd[0]);
        close(pipefd[1]);
        *exit_code = e;
        return strdup(strerror(e));
    }

    if (pid == 0) {
        close(pipefd[0]);
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[1]);
        execv(path, argv);
        _exit(127);
    }

    close(pipefd[1]);
    char *out = calloc(1, MAX_OUTPUT + 1);
    if (!out) {
        close(pipefd[0]);
        kill(pid, SIGKILL);
        waitpid(pid, NULL, 0);
        *exit_code = ENOMEM;
        return strdup("out of memory");
    }

    size_t used = 0;
    while (used < MAX_OUTPUT) {
        ssize_t n = read(pipefd[0], out + used, MAX_OUTPUT - used);
        if (n > 0) {
            used += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        break;
    }
    close(pipefd[0]);
    out[used] = 0;

    int status = 0;
    waitpid(pid, &status, 0);
    if (WIFEXITED(status)) *exit_code = WEXITSTATUS(status);
    else if (WIFSIGNALED(status)) *exit_code = 128 + WTERMSIG(status);
    else *exit_code = -1;
    return out;
}

static bool na_valid_simple_id(const char *value, size_t maxLen) {
    if (!value || !*value) return false;
    size_t n = strlen(value);
    if (n == 0 || n > maxLen) return false;
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)value[i];
        if (!(isalnum(c) || c == '.' || c == '-' || c == '_' || c == '+')) return false;
    }
    return true;
}

static const char *na_find_tool(const char *name, char out[4096]) {
    if (!name || !*name) return NULL;

    char jbroot[4096] = {0};
    if (detect_jbroot(jbroot)) {
        const char *folders[] = { "usr/bin", "bin", "usr/sbin", "sbin" };
        for (size_t i = 0; i < sizeof(folders)/sizeof(folders[0]); i++) {
            snprintf(out, 4096, "%s/%s/%s", jbroot, folders[i], name);
            if (access(out, X_OK) == 0) return out;
        }
    }

    const char *roots[] = { "/usr/bin", "/bin", "/usr/sbin", "/sbin" };
    for (size_t i = 0; i < sizeof(roots)/sizeof(roots[0]); i++) {
        snprintf(out, 4096, "%s/%s", roots[i], name);
        if (access(out, X_OK) == 0) return out;
    }
    return NULL;
}

static bool na_safe_mutation_path(const char *raw, char resolved[4096]) {
    if (!raw || !*raw || !sane_path(raw)) return false;
    const char *p = resolve_rootfs_path(raw, resolved);
    if (!p || !sane_path(p) || sensitive_path(p)) return false;

    size_t n = strlen(p);
    if (n < 8) return false;

    static const char *blockedExact[] = {
        "/", "/private", "/var", "/private/var",
        "/System", "/usr", "/bin", "/sbin", "/Applications",
        "/var/mobile", "/private/var/mobile"
    };
    for (size_t i = 0; i < sizeof(blockedExact)/sizeof(blockedExact[0]); i++) {
        if (!strcmp(p, blockedExact[i])) return false;
    }

    char jbroot[4096] = {0};
    if (detect_jbroot(jbroot) && !strcmp(p, jbroot)) return false;

    bool allowed =
        !strncmp(p, "/var/mobile/", 12) ||
        !strncmp(p, "/private/var/mobile/", 20) ||
        !strncmp(p, "/var/tmp/", 9) ||
        !strncmp(p, "/private/var/tmp/", 17) ||
        !strncmp(p, "/tmp/", 5) ||
        !strncmp(p, "/var/root/Library/Preferences/", 30) ||
        !strncmp(p, "/private/var/root/Library/Preferences/", 38) ||
        (detect_jbroot(jbroot) && !strncmp(p, jbroot, strlen(jbroot)) && p[strlen(jbroot)] == '/');

    return allowed;
}

static char *action_button_v07(const char *arg, int *ok) {
    if (!na_hid_load()) {
        *ok = 0;
        return strdup(na_hid_error);
    }

    uint16_t usage = 0;
    if (!strcmp(arg, "home")) usage = 0x40;
    else if (!strcmp(arg, "power")) usage = 0x30;
    else if (!strcmp(arg, "mute")) usage = 0xE2;
    else if (!strcmp(arg, "volume_up")) usage = 0xE9;
    else if (!strcmp(arg, "volume_down")) usage = 0xEA;
    else {
        *ok = 0;
        return strdup("button must be home, power, mute, volume_up or volume_down");
    }

    NAHIDEventRef down = na_create_keyboard_event(kCFAllocatorDefault, na_hid_now(), 0x0C, usage, true, 0);
    if (!na_hid_dispatch(down)) {
        *ok = 0;
        return strdup("button down dispatch failed");
    }
    usleep(90 * 1000);
    NAHIDEventRef up = na_create_keyboard_event(kCFAllocatorDefault, na_hid_now(), 0x0C, usage, false, 0);
    if (!na_hid_dispatch(up)) {
        *ok = 0;
        return strdup("button up dispatch failed");
    }

    *ok = 1;
    return strdup("button dispatched");
}

static char *action_package_install_v07(const char *arg, int *ok) {
    if (!arg || !*arg) {
        *ok = 0;
        return strdup("missing DEB path");
    }

    char resolved[4096];
    const char *path = resolve_rootfs_path(arg, resolved);
    if (!path || !sane_path(path) || sensitive_path(path)) {
        *ok = 0;
        return strdup("invalid or blocked DEB path");
    }
    size_t len = strlen(path);
    if (len < 5 || strcasecmp(path + len - 4, ".deb")) {
        *ok = 0;
        return strdup("package_install accepts a .deb file");
    }

    bool sourceAllowed =
        !strncmp(path, "/var/mobile/", 12) ||
        !strncmp(path, "/private/var/mobile/", 20) ||
        !strncmp(path, "/tmp/", 5) ||
        !strncmp(path, "/var/tmp/", 9) ||
        !strncmp(path, "/private/var/tmp/", 17);
    if (!sourceAllowed || access(path, R_OK) != 0) {
        *ok = 0;
        return strdup("DEB must be a readable file under /var/mobile or a temporary directory");
    }

    char tool[4096];
    const char *dpkg = na_find_tool("dpkg", tool);
    if (!dpkg) {
        *ok = 0;
        return strdup("dpkg not found in the RootHide bootstrap");
    }

    char *argv[] = { (char *)dpkg, "-i", (char *)path, NULL };
    int code = 0;
    char *output = na_run_argv_capture(dpkg, argv, &code);
    *ok = code == 0;
    return output;
}

static char *action_package_remove_v07(const char *arg, int *ok) {
    if (!na_valid_simple_id(arg, 180)) {
        *ok = 0;
        return strdup("invalid package identifier");
    }

    char tool[4096];
    const char *dpkg = na_find_tool("dpkg", tool);
    if (!dpkg) {
        *ok = 0;
        return strdup("dpkg not found in the RootHide bootstrap");
    }

    char *argv[] = { (char *)dpkg, "-r", (char *)arg, NULL };
    int code = 0;
    char *output = na_run_argv_capture(dpkg, argv, &code);
    *ok = code == 0;
    return output;
}

static char *action_ldrestart_v07(int *ok) {
    char tool[4096];
    const char *bin = na_find_tool("ldrestart", tool);
    if (!bin) {
        *ok = 0;
        return strdup("ldrestart is not installed in the bootstrap");
    }
    char *argv[] = { (char *)bin, NULL };
    int code = 0;
    char *output = na_run_argv_capture(bin, argv, &code);
    *ok = code == 0;
    return output;
}

static char *action_userspace_reboot_v07(int *ok) {
    char tool[4096];
    const char *launchctl = na_find_tool("launchctl", tool);
    if (!launchctl) {
        *ok = 0;
        return strdup("launchctl unavailable");
    }
    char *argv[] = { (char *)launchctl, "reboot", "userspace", NULL };
    int code = 0;
    char *output = na_run_argv_capture(launchctl, argv, &code);
    *ok = code == 0;
    return output;
}

static char *na_launchctl_domain_action(const char *verb, const char *label, bool killFirst, int *ok) {
    if (!na_valid_simple_id(label, 220)) {
        *ok = 0;
        return strdup("invalid service label");
    }

    char tool[4096];
    const char *launchctl = na_find_tool("launchctl", tool);
    if (!launchctl) {
        *ok = 0;
        return strdup("launchctl unavailable");
    }

    const char *domains[] = { "user/501", "system" };
    char target[512];

    for (size_t i = 0; i < sizeof(domains)/sizeof(domains[0]); i++) {
        snprintf(target, sizeof(target), "%s/%s", domains[i], label);

        int code = 0;
        char *output = NULL;

        if (!strcmp(verb, "status")) {
            char *argv[] = { (char *)launchctl, "print", target, NULL };
            output = na_run_argv_capture(launchctl, argv, &code);
        } else if (!strcmp(verb, "start")) {
            char *argv[] = { (char *)launchctl, "kickstart", target, NULL };
            output = na_run_argv_capture(launchctl, argv, &code);
        } else if (!strcmp(verb, "restart")) {
            char *argv[] = { (char *)launchctl, "kickstart", "-k", target, NULL };
            output = na_run_argv_capture(launchctl, argv, &code);
        } else if (!strcmp(verb, "stop") || killFirst) {
            char *argv[] = { (char *)launchctl, "kill", "SIGTERM", target, NULL };
            output = na_run_argv_capture(launchctl, argv, &code);
        } else {
            *ok = 0;
            return strdup("unsupported service action");
        }

        if (code == 0) {
            *ok = 1;
            return output;
        }
        free(output);
    }

    *ok = 0;
    return strdup("service action failed in user/501 and system domains");
}

static char *action_service_list_v07(int *ok) {
    char tool[4096];
    const char *launchctl = na_find_tool("launchctl", tool);
    if (!launchctl) {
        *ok = 0;
        return strdup("launchctl unavailable");
    }

    char *argv[] = { (char *)launchctl, "print", "user/501", NULL };
    int code = 0;
    char *output = na_run_argv_capture(launchctl, argv, &code);
    if (code != 0) {
        free(output);
        char *argv2[] = { (char *)launchctl, "print", "system", NULL };
        output = na_run_argv_capture(launchctl, argv2, &code);
    }
    *ok = code == 0;
    return output;
}

static char *action_root_stat_v07(const char *arg, int *ok) {
    if (!sane_path(arg)) {
        *ok = 0;
        return strdup("path is blocked or invalid");
    }

    char resolvedBuf[4096];
    const char *resolved = resolve_rootfs_path(arg, resolvedBuf);
    if (!sane_path(resolved)) {
        *ok = 0;
        return strdup("resolved path is blocked or invalid");
    }

    struct stat st;
    if (lstat(resolved, &st) != 0) {
        *ok = 0;
        return strdup(strerror(errno));
    }

    char *e1 = json_escape(arg);
    char *e2 = json_escape(resolved);
    char buffer[8192];
    snprintf(
        buffer, sizeof(buffer),
        "{\"path\":\"%s\",\"resolved\":\"%s\",\"size\":%lld,\"mode\":%u,\"uid\":%u,\"gid\":%u,\"directory\":%s,\"symlink\":%s,\"mtime\":%lld}",
        e1 ? e1 : "",
        e2 ? e2 : "",
        (long long)st.st_size,
        (unsigned int)(st.st_mode & 07777),
        (unsigned int)st.st_uid,
        (unsigned int)st.st_gid,
        S_ISDIR(st.st_mode) ? "true" : "false",
        S_ISLNK(st.st_mode) ? "true" : "false",
        (long long)st.st_mtime
    );
    free(e1);
    free(e2);
    *ok = 1;
    return strdup(buffer);
}

static char *action_root_mkdir_v07(const char *arg, int *ok) {
    char resolved[4096];
    if (!na_safe_mutation_path(arg, resolved)) {
        *ok = 0;
        return strdup("path is outside allowed mutable roots or is blocked");
    }

    char tool[4096];
    const char *mkdirbin = na_find_tool("mkdir", tool);
    if (!mkdirbin) {
        *ok = 0;
        return strdup("mkdir unavailable");
    }
    char *argv[] = { (char *)mkdirbin, "-p", resolved, NULL };
    int code = 0;
    char *output = na_run_argv_capture(mkdirbin, argv, &code);
    *ok = code == 0;
    return output;
}

static char *na_two_path_action(const char *toolName, const char *arg, bool recursive, int *ok) {
    const char *separator = strchr(arg ?: "", '\n');
    if (!separator) {
        *ok = 0;
        return strdup("expected source and destination separated by newline");
    }

    char sourceRaw[4096] = {0};
    size_t sourceLen = (size_t)(separator - arg);
    if (sourceLen == 0 || sourceLen >= sizeof(sourceRaw)) {
        *ok = 0;
        return strdup("invalid source path");
    }
    memcpy(sourceRaw, arg, sourceLen);
    sourceRaw[sourceLen] = 0;
    const char *destRaw = separator + 1;

    char source[4096], dest[4096];
    if (!na_safe_mutation_path(sourceRaw, source) || !na_safe_mutation_path(destRaw, dest)) {
        *ok = 0;
        return strdup("source or destination is outside allowed mutable roots");
    }

    char tool[4096];
    const char *bin = na_find_tool(toolName, tool);
    if (!bin) {
        *ok = 0;
        return strdup("required file utility is unavailable");
    }

    int code = 0;
    char *output = NULL;
    if (recursive) {
        char *argv[] = { (char *)bin, "-R", source, dest, NULL };
        output = na_run_argv_capture(bin, argv, &code);
    } else {
        char *argv[] = { (char *)bin, source, dest, NULL };
        output = na_run_argv_capture(bin, argv, &code);
    }
    *ok = code == 0;
    return output;
}

static char *action_root_delete_v07(const char *arg, int *ok) {
    char resolved[4096];
    if (!na_safe_mutation_path(arg, resolved)) {
        *ok = 0;
        return strdup("path is outside allowed mutable roots or is protected");
    }

    char tool[4096];
    const char *rm = na_find_tool("rm", tool);
    if (!rm) {
        *ok = 0;
        return strdup("rm unavailable");
    }
    char *argv[] = { (char *)rm, "-rf", resolved, NULL };
    int code = 0;
    char *output = na_run_argv_capture(rm, argv, &code);
    *ok = code == 0;
    return output;
}

static char *action_root_write_v07(const char *arg, int *ok) {
    const char *separator = strchr(arg ?: "", '\n');
    if (!separator) {
        *ok = 0;
        return strdup("expected path then newline then UTF-8 text");
    }

    char rawPath[4096] = {0};
    size_t pathLen = (size_t)(separator - arg);
    if (pathLen == 0 || pathLen >= sizeof(rawPath)) {
        *ok = 0;
        return strdup("invalid path");
    }
    memcpy(rawPath, arg, pathLen);
    rawPath[pathLen] = 0;
    const char *text = separator + 1;
    if (strlen(text) > 262144) {
        *ok = 0;
        return strdup("text exceeds 256 KiB limit");
    }

    char resolved[4096];
    if (!na_safe_mutation_path(rawPath, resolved)) {
        *ok = 0;
        return strdup("path is outside allowed mutable roots or is protected");
    }

    int fd = open(resolved, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (fd < 0) {
        *ok = 0;
        return strdup(strerror(errno));
    }

    size_t len = strlen(text);
    size_t off = 0;
    while (off < len) {
        ssize_t n = write(fd, text + off, len - off);
        if (n > 0) {
            off += (size_t)n;
            continue;
        }
        if (n < 0 && errno == EINTR) continue;
        int e = errno;
        close(fd);
        *ok = 0;
        return strdup(strerror(e));
    }
    fsync(fd);
    close(fd);
    *ok = 1;
    return strdup("file written");
}

static bool na_case_contains(const char *haystack, const char *needle) {
    if (!haystack || !needle) return false;
    size_t hn = strlen(haystack), nn = strlen(needle);
    if (nn == 0) return true;
    if (nn > hn) return false;

    for (size_t i = 0; i + nn <= hn; i++) {
        bool match = true;
        for (size_t j = 0; j < nn; j++) {
            if (tolower((unsigned char)haystack[i+j]) != tolower((unsigned char)needle[j])) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

static void na_search_walk(
    const char *dirPath,
    const char *needle,
    int depth,
    int maxDepth,
    char *out,
    size_t cap,
    size_t *used,
    int *count
) {
    if (*count >= 500 || depth > maxDepth || *used + 128 >= cap) return;
    if (sensitive_path(dirPath)) return;

    DIR *dir = opendir(dirPath);
    if (!dir) return;

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL && *count < 500) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;

        char full[4096];
        if (snprintf(full, sizeof(full), "%s/%s", dirPath, entry->d_name) >= (int)sizeof(full)) continue;
        if (sensitive_path(full)) continue;

        struct stat st;
        if (lstat(full, &st) != 0) continue;

        if (na_case_contains(entry->d_name, needle)) {
            char *escaped = json_escape(full);
            int n = snprintf(out + *used, cap - *used, "%s\"%s\"", *count ? "," : "", escaped ? escaped : "");
            free(escaped);
            if (n <= 0 || *used + (size_t)n >= cap) break;
            *used += (size_t)n;
            (*count)++;
        }

        if (S_ISDIR(st.st_mode) && !S_ISLNK(st.st_mode)) {
            na_search_walk(full, needle, depth + 1, maxDepth, out, cap, used, count);
        }
    }

    closedir(dir);
}

static char *action_root_search_v07(const char *arg, int *ok) {
    const char *separator = strchr(arg ?: "", '\n');
    if (!separator) {
        *ok = 0;
        return strdup("expected root path then newline then search text");
    }

    char rawRoot[4096] = {0};
    size_t rootLen = (size_t)(separator - arg);
    if (rootLen == 0 || rootLen >= sizeof(rawRoot)) {
        *ok = 0;
        return strdup("invalid root path");
    }
    memcpy(rawRoot, arg, rootLen);
    rawRoot[rootLen] = 0;
    const char *needle = separator + 1;
    if (!*needle || strlen(needle) > 128) {
        *ok = 0;
        return strdup("search text must be 1 to 128 characters");
    }

    if (!sane_path(rawRoot)) {
        *ok = 0;
        return strdup("root path is blocked or invalid");
    }

    char resolvedBuf[4096];
    const char *resolved = resolve_rootfs_path(rawRoot, resolvedBuf);
    if (!sane_path(resolved) || sensitive_path(resolved)) {
        *ok = 0;
        return strdup("resolved root is blocked");
    }

    char *out = calloc(1, MAX_OUTPUT + 1);
    if (!out) {
        *ok = 0;
        return strdup("out of memory");
    }
    size_t used = 0;
    int count = 0;
    used += snprintf(out + used, MAX_OUTPUT - used, "{\"matches\":[");
    na_search_walk(resolved, needle, 0, 6, out, MAX_OUTPUT, &used, &count);
    used += snprintf(out + used, MAX_OUTPUT - used, "],\"count\":%d,\"truncated\":%s}", count, count >= 500 ? "true" : "false");
    out[used] = 0;
    *ok = 1;
    return out;
}

static char *action_archive_v07(const char *arg, bool extract, int *ok) {
    const char *separator = strchr(arg ?: "", '\n');
    if (!separator) {
        *ok = 0;
        return strdup("expected source and destination separated by newline");
    }

    char sourceRaw[4096] = {0};
    size_t sourceLen = (size_t)(separator - arg);
    if (sourceLen == 0 || sourceLen >= sizeof(sourceRaw)) {
        *ok = 0;
        return strdup("invalid source path");
    }
    memcpy(sourceRaw, arg, sourceLen);
    sourceRaw[sourceLen] = 0;
    const char *destRaw = separator + 1;

    char source[4096], dest[4096];
    if (!na_safe_mutation_path(sourceRaw, source) || !na_safe_mutation_path(destRaw, dest)) {
        *ok = 0;
        return strdup("archive paths are outside allowed mutable roots");
    }

    char tool[4096];
    const char *bin = na_find_tool(extract ? "unzip" : "zip", tool);
    if (!bin) {
        *ok = 0;
        return strdup(extract ? "unzip utility is not installed" : "zip utility is not installed");
    }

    int code = 0;
    char *output = NULL;
    if (extract) {
        char *argv[] = { (char *)bin, "-o", source, "-d", dest, NULL };
        output = na_run_argv_capture(bin, argv, &code);
    } else {
        char *argv[] = { (char *)bin, "-r", dest, source, NULL };
        output = na_run_argv_capture(bin, argv, &code);
    }
    *ok = code == 0;
    return output;
}
