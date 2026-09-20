#define _DARWIN_C_SOURCE 1
#include <arpa/inet.h>
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define NEXTAGENTD_VERSION "0.3.0"
#define LISTEN_PORT 37589
#define MAX_LINE 65536
#define MAX_OUTPUT 524288
#define TOKEN_DIR "/var/mobile/Library/NextAgent"
#define TOKEN_PATH TOKEN_DIR "/daemon.token"

static void logmsg(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    fprintf(stderr, "[nextagentd] ");
    vfprintf(stderr, fmt, ap);
    fprintf(stderr, "\n");
    va_end(ap);
}

static int ensure_dir(const char *path, mode_t mode, uid_t uid, gid_t gid) {
    struct stat st;
    if (stat(path, &st) == 0) {
        if (!S_ISDIR(st.st_mode)) return -1;
    } else if (mkdir(path, mode) != 0 && errno != EEXIST) {
        return -1;
    }
    chmod(path, mode);
    chown(path, uid, gid);
    return 0;
}

static int random_bytes(unsigned char *buf, size_t n) {
    int fd = open("/dev/urandom", O_RDONLY);
    if (fd < 0) return -1;
    size_t off = 0;
    while (off < n) {
        ssize_t r = read(fd, buf + off, n - off);
        if (r <= 0) { close(fd); return -1; }
        off += (size_t)r;
    }
    close(fd);
    return 0;
}

static int ensure_token(char out[65]) {
    if (ensure_dir("/var/mobile/Library", 0755, 501, 501) != 0 && errno != EEXIST) {
        // Usually already exists; do not fail solely on ownership restrictions.
    }
    if (ensure_dir(TOKEN_DIR, 0700, 501, 501) != 0) return -1;

    FILE *f = fopen(TOKEN_PATH, "r");
    if (f) {
        char buf[96] = {0};
        if (fgets(buf, sizeof(buf), f)) {
            fclose(f);
            size_t len = strcspn(buf, "\r\n");
            buf[len] = 0;
            if (len == 64) {
                memcpy(out, buf, 65);
                chmod(TOKEN_PATH, 0600);
                chown(TOKEN_PATH, 501, 501);
                return 0;
            }
        } else fclose(f);
    }

    unsigned char rnd[32];
    if (random_bytes(rnd, sizeof(rnd)) != 0) return -1;
    static const char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < sizeof(rnd); i++) {
        out[i*2] = hex[(rnd[i] >> 4) & 0xf];
        out[i*2+1] = hex[rnd[i] & 0xf];
    }
    out[64] = 0;
    f = fopen(TOKEN_PATH, "w");
    if (!f) return -1;
    fprintf(f, "%s\n", out);
    fclose(f);
    chmod(TOKEN_PATH, 0600);
    chown(TOKEN_PATH, 501, 501);
    return 0;
}

static bool sensitive_path(const char *p) {
    static const char *blocked[] = {
        "/var/Keychains", "/private/var/Keychains",
        "/var/mobile/Library/Keychains", "/private/var/mobile/Library/Keychains",
        "/var/mobile/Library/Accounts", "/private/var/mobile/Library/Accounts",
        "/var/mobile/Library/Safari/History", "/private/var/mobile/Library/Safari/History",
        "/var/mobile/Library/Messages", "/private/var/mobile/Library/Messages",
        "/var/mobile/Library/Mail", "/private/var/mobile/Library/Mail",
        "/var/mobile/Library/AddressBook", "/private/var/mobile/Library/AddressBook"
    };
    for (size_t i = 0; i < sizeof(blocked)/sizeof(blocked[0]); i++) {
        size_t n = strlen(blocked[i]);
        if (strncmp(p, blocked[i], n) == 0 && (p[n] == 0 || p[n] == '/')) return true;
    }
    return false;
}

static bool sane_path(const char *p) {
    if (!p || p[0] != '/') return false;
    if (strstr(p, "\n") || strstr(p, "\r")) return false;
    return !sensitive_path(p);
}

static char *run_fixed(const char *cmd, int *exit_code) {
    FILE *fp = popen(cmd, "r");
    if (!fp) {
        *exit_code = errno;
        return strdup("popen failed");
    }
    char *out = calloc(1, MAX_OUTPUT + 1);
    if (!out) { pclose(fp); *exit_code = ENOMEM; return strdup("out of memory"); }
    size_t used = 0;
    while (used < MAX_OUTPUT) {
        size_t r = fread(out + used, 1, MAX_OUTPUT - used, fp);
        used += r;
        if (r == 0) break;
    }
    out[used] = 0;
    int st = pclose(fp);
    if (WIFEXITED(st)) *exit_code = WEXITSTATUS(st); else *exit_code = -1;
    return out;
}

static char *json_escape(const char *s) {
    size_t cap = strlen(s) * 2 + 32;
    char *o = malloc(cap);
    if (!o) return NULL;
    size_t j = 0;
    for (size_t i = 0; s[i]; i++) {
        unsigned char c = (unsigned char)s[i];
        const char *rep = NULL;
        if (c == '\\') rep = "\\\\";
        else if (c == '"') rep = "\\\"";
        else if (c == '\n') rep = "\\n";
        else if (c == '\r') rep = "\\r";
        else if (c == '\t') rep = "\\t";
        if (rep) {
            size_t n = strlen(rep);
            if (j + n + 1 >= cap) { cap *= 2; o = realloc(o, cap); if (!o) return NULL; }
            memcpy(o + j, rep, n); j += n;
        } else if (c >= 0x20) {
            if (j + 2 >= cap) { cap *= 2; o = realloc(o, cap); if (!o) return NULL; }
            o[j++] = (char)c;
        }
    }
    o[j] = 0;
    return o;
}

static char *action_ping(void) {
    char buf[512];
    snprintf(buf, sizeof(buf), "{\"version\":\"%s\",\"pid\":%d,\"uid\":%d,\"euid\":%d,\"root\":%s}",
             NEXTAGENTD_VERSION, getpid(), getuid(), geteuid(), geteuid() == 0 ? "true" : "false");
    return strdup(buf);
}

static char *action_jailbreak(void) {
    const char *paths[] = {
        "/var/jb", "/private/preboot", "/Applications",
        "/var/jb/usr/bin/dpkg", "/usr/bin/dpkg",
        "/var/jb/usr/bin/apt", "/usr/bin/apt",
        "/var/jb/Applications/Sileo.app", "/Applications/Sileo.app",
        "/var/jb/Applications/Zebra.app", "/Applications/Zebra.app",
        "/var/jb/usr/lib/libellekit.dylib", "/var/jb/usr/lib/libsubstitute.dylib"
    };
    char *out = calloc(1, 8192);
    if (!out) return strdup("memory error");
    strcat(out, "{\"daemon_root\":");
    strcat(out, geteuid() == 0 ? "true" : "false");
    strcat(out, ",\"present_paths\":[");
    bool first = true;
    for (size_t i = 0; i < sizeof(paths)/sizeof(paths[0]); i++) {
        if (access(paths[i], F_OK) == 0) {
            char *e = json_escape(paths[i]);
            if (!first) strcat(out, ",");
            strcat(out, "\""); strcat(out, e ? e : ""); strcat(out, "\"");
            free(e); first = false;
        }
    }
    strcat(out, "]}");
    return out;
}

static char *action_list(const char *path, int *ok) {
    if (!sane_path(path)) { *ok = 0; return strdup("path is blocked or invalid"); }
    DIR *d = opendir(path);
    if (!d) { *ok = 0; return strdup(strerror(errno)); }
    size_t cap = 65536, used = 0;
    char *out = malloc(cap);
    if (!out) { closedir(d); *ok = 0; return strdup("memory error"); }
    used += snprintf(out + used, cap - used, "{\"path\":\"%s\",\"items\":[", path);
    struct dirent *ent;
    int count = 0;
    bool first = true;
    while ((ent = readdir(d)) != NULL && count < 1000) {
        if (!strcmp(ent->d_name, ".") || !strcmp(ent->d_name, "..")) continue;
        char full[4096];
        snprintf(full, sizeof(full), "%s/%s", path, ent->d_name);
        struct stat st;
        memset(&st, 0, sizeof(st));
        lstat(full, &st);
        char *e = json_escape(ent->d_name);
        char item[8192];
        snprintf(item, sizeof(item), "%s{\"name\":\"%s\",\"directory\":%s,\"size\":%lld}",
                 first ? "" : ",", e ? e : "", S_ISDIR(st.st_mode) ? "true" : "false", (long long)st.st_size);
        free(e);
        size_t n = strlen(item);
        if (used + n + 4 >= cap) break;
        memcpy(out + used, item, n); used += n;
        first = false; count++;
    }
    closedir(d);
    used += snprintf(out + used, cap - used, "]}");
    out[used] = 0;
    *ok = 1;
    return out;
}

static char *action_read(const char *path, int *ok) {
    if (!sane_path(path)) { *ok = 0; return strdup("path is blocked or invalid"); }
    int fd = open(path, O_RDONLY);
    if (fd < 0) { *ok = 0; return strdup(strerror(errno)); }
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) { close(fd); *ok = 0; return strdup("not a regular file"); }
    size_t want = (size_t)(st.st_size > 262144 ? 262144 : st.st_size);
    char *buf = malloc(want + 64);
    if (!buf) { close(fd); *ok = 0; return strdup("memory error"); }
    size_t used = 0;
    while (used < want) {
        ssize_t r = read(fd, buf + used, want - used);
        if (r < 0) { free(buf); close(fd); *ok = 0; return strdup(strerror(errno)); }
        if (r == 0) break;
        used += (size_t)r;
    }
    close(fd);
    for (size_t i = 0; i < used; i++) {
        unsigned char c = (unsigned char)buf[i];
        if (c == 0) { free(buf); *ok = 0; return strdup("binary/NUL-containing file blocked"); }
    }
    if ((off_t)used < st.st_size) {
        const char *t = "\n[truncated by nextagentd]\n";
        size_t n = strlen(t); memcpy(buf + used, t, n); used += n;
    }
    buf[used] = 0;
    *ok = 1;
    return buf;
}

static char *action_ps(int *ok) {
    int code = 0;
    char *r = run_fixed("PATH=/var/jb/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin ps -axo pid,user,comm | head -n 350 2>&1", &code);
    *ok = (code == 0);
    return r;
}

static char *action_uicache(int *ok) {
    int code = 0;
    char *r = run_fixed("PATH=/var/jb/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin; if command -v uicache >/dev/null 2>&1; then uicache -a 2>&1; else echo 'uicache not found'; exit 127; fi", &code);
    *ok = (code == 0);
    return r;
}

static char *action_respring(int *ok) {
    int code = 0;
    char *r = run_fixed("PATH=/var/jb/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin; if command -v sbreload >/dev/null 2>&1; then sbreload 2>&1; else killall SpringBoard 2>&1; fi", &code);
    *ok = (code == 0);
    return r;
}

static char *action_kill(const char *arg, int *ok) {
    if (!arg || !*arg) { *ok = 0; return strdup("missing pid"); }
    for (const char *p = arg; *p; p++) if (!isdigit((unsigned char)*p)) { *ok = 0; return strdup("invalid pid"); }
    long pid = strtol(arg, NULL, 10);
    if (pid <= 20 || pid > 999999) { *ok = 0; return strdup("protected or invalid pid"); }
    if (kill((pid_t)pid, SIGTERM) != 0) { *ok = 0; return strdup(strerror(errno)); }
    *ok = 1; return strdup("SIGTERM sent");
}

static int b64val(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

static char *base64_decode(const char *in) {
    if (!in || !strcmp(in, "-")) return strdup("");
    size_t len = strlen(in);
    char *out = malloc(len * 3 / 4 + 4);
    if (!out) return NULL;
    size_t oi = 0;
    int val = 0, valb = -8;
    for (size_t i = 0; i < len; i++) {
        if (in[i] == '=') break;
        int v = b64val(in[i]);
        if (v < 0) continue;
        val = (val << 6) + v;
        valb += 6;
        if (valb >= 0) {
            out[oi++] = (char)((val >> valb) & 0xff);
            valb -= 8;
        }
    }
    out[oi] = 0;
    return out;
}

static int send_response(int fd, bool ok, const char *payload) {
    if (!payload) payload = "";
    size_t n = strlen(payload);
    char header[64];
    int hn = snprintf(header, sizeof(header), "%s %zu\n", ok ? "OK" : "ERR", n);
    if (write(fd, header, (size_t)hn) != hn) return -1;
    size_t off = 0;
    while (off < n) {
        ssize_t w = write(fd, payload + off, n - off);
        if (w <= 0) return -1;
        off += (size_t)w;
    }
    return 0;
}

static void handle_client(int fd, const char *token) {
    char line[MAX_LINE];
    size_t used = 0;
    while (used + 1 < sizeof(line)) {
        char c;
        ssize_t r = read(fd, &c, 1);
        if (r <= 0) return;
        if (c == '\n') break;
        line[used++] = c;
    }
    line[used] = 0;

    char *save = NULL;
    char *magic = strtok_r(line, " ", &save);
    char *provided = strtok_r(NULL, " ", &save);
    char *action = strtok_r(NULL, " ", &save);
    char *arg64 = strtok_r(NULL, " ", &save);
    if (!magic || strcmp(magic, "NAGENT1") || !provided || !action || strcmp(provided, token) != 0) {
        send_response(fd, false, "authentication failed");
        return;
    }
    char *arg = base64_decode(arg64 ? arg64 : "-");
    if (!arg) { send_response(fd, false, "decode failed"); return; }

    int ok_i = 1;
    char *out = NULL;
    if (!strcmp(action, "ping")) out = action_ping();
    else if (!strcmp(action, "jailbreak_info")) out = action_jailbreak();
    else if (!strcmp(action, "ps")) out = action_ps(&ok_i);
    else if (!strcmp(action, "list")) { out = action_list(arg, &ok_i); }
    else if (!strcmp(action, "read")) { out = action_read(arg, &ok_i); }
    else if (!strcmp(action, "uicache")) { out = action_uicache(&ok_i); }
    else if (!strcmp(action, "respring")) { out = action_respring(&ok_i); }
    else if (!strcmp(action, "kill")) { out = action_kill(arg, &ok_i); }
    else { ok_i = 0; out = strdup("unknown daemon action"); }

    send_response(fd, ok_i != 0, out ? out : "");
    free(out);
    free(arg);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    if (geteuid() != 0) {
        logmsg("refusing to start without root; euid=%d", geteuid());
        return 77;
    }
    char token[65] = {0};
    if (ensure_token(token) != 0) {
        logmsg("failed to create/read token at %s: %s", TOKEN_PATH, strerror(errno));
        return 78;
    }

    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return 79;
    int yes = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(LISTEN_PORT);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        logmsg("bind failed: %s", strerror(errno)); close(s); return 80;
    }
    if (listen(s, 8) != 0) { close(s); return 81; }
    logmsg("v%s listening on 127.0.0.1:%d as uid=%d euid=%d", NEXTAGENTD_VERSION, LISTEN_PORT, getuid(), geteuid());

    for (;;) {
        int c = accept(s, NULL, NULL);
        if (c < 0) { if (errno == EINTR) continue; sleep(1); continue; }
        handle_client(c, token);
        close(c);
    }
    return 0;
}
