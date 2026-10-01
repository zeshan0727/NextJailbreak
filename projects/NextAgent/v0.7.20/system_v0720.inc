/*
 * Next Agent v0.7.20 root-routing hardening.
 * Uses the already authenticated root daemon and RootHide-aware tool resolver
 * from system_v07.inc. No arbitrary shell command surface is exposed.
 */

static char *action_root_exec_probe_v0720(int *ok) {
    if (geteuid() != 0) {
        *ok = 0;
        char buf[256];
        snprintf(buf, sizeof(buf), "daemon is not root (uid=%d euid=%d)", getuid(), geteuid());
        return strdup(buf);
    }

    char idPath[4096] = {0};
    const char *idbin = na_find_tool("id", idPath);
    if (!idbin) {
        *ok = 0;
        return strdup("root probe could not resolve id through the RootHide-aware tool path");
    }

    char *argv[] = { (char *)idbin, "-u", NULL };
    int code = 0;
    char *output = na_run_argv_capture(idbin, argv, &code);
    if (!output) {
        *ok = 0;
        return strdup("root probe produced no output");
    }

    size_t n = strlen(output);
    while (n > 0 && (output[n - 1] == '\n' || output[n - 1] == '\r' || output[n - 1] == ' ' || output[n - 1] == '\t')) {
        output[--n] = 0;
    }

    if (code != 0 || strcmp(output, "0") != 0) {
        char *escaped = json_escape(output);
        char buf[1024];
        snprintf(
            buf, sizeof(buf),
            "{\"executed\":false,\"exit_code\":%d,\"reported_uid\":\"%s\",\"daemon_euid\":%d}",
            code,
            escaped ? escaped : "",
            geteuid()
        );
        free(escaped);
        free(output);
        *ok = 0;
        return strdup(buf);
    }
    free(output);

    char jbroot[4096] = {0};
    bool hasJbroot = detect_jbroot(jbroot);

    char uicachePath[4096] = {0};
    const char *uicache = na_find_tool("uicache", uicachePath);

    char *escapedId = json_escape(idbin);
    char *escapedJb = json_escape(hasJbroot ? jbroot : "");
    char *escapedUICache = json_escape(uicache ? uicache : "");

    char buf[16384];
    snprintf(
        buf, sizeof(buf),
        "{\"executed\":true,\"reported_uid\":0,\"daemon_uid\":%d,\"daemon_euid\":%d,"
        "\"id_path\":\"%s\",\"roothide\":%s,\"jbroot\":\"%s\",\"uicache_path\":\"%s\"}",
        getuid(),
        geteuid(),
        escapedId ? escapedId : "",
        roothide_mode() ? "true" : "false",
        escapedJb ? escapedJb : "",
        escapedUICache ? escapedUICache : ""
    );

    free(escapedId);
    free(escapedJb);
    free(escapedUICache);

    *ok = 1;
    return strdup(buf);
}

static char *action_uicache_v0720(int *ok) {
    char tool[4096] = {0};
    const char *bin = na_find_tool("uicache", tool);
    if (!bin) {
        *ok = 0;
        return strdup("uicache was not found through the RootHide-aware bootstrap path");
    }

    char *argv[] = { (char *)bin, "-a", NULL };
    int code = 0;
    char *output = na_run_argv_capture(bin, argv, &code);
    *ok = code == 0;
    return output;
}

static char *action_respring_v0720(int *ok) {
    char tool[4096] = {0};
    const char *sbreload = na_find_tool("sbreload", tool);
    if (sbreload) {
        char *argv[] = { (char *)sbreload, NULL };
        int code = 0;
        char *output = na_run_argv_capture(sbreload, argv, &code);
        *ok = code == 0;
        return output;
    }

    char killallPath[4096] = {0};
    const char *killall = na_find_tool("killall", killallPath);
    if (!killall) {
        *ok = 0;
        return strdup("neither sbreload nor killall could be resolved through the RootHide-aware bootstrap path");
    }

    char *argv[] = { (char *)killall, "SpringBoard", NULL };
    int code = 0;
    char *output = na_run_argv_capture(killall, argv, &code);
    *ok = code == 0;
    return output;
}
