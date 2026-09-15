#import "LTSpawnRoot.h"
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

#ifndef POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
#endif
extern int posix_spawnattr_set_persona_np(posix_spawnattr_t * __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(posix_spawnattr_t * __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(posix_spawnattr_t * __restrict, uid_t);

static int LTSpawnRootAtPath(NSString *path, NSArray<NSString *> *arguments, BOOL embedded, NSString **output) {
    NSMutableArray<NSString *> *argvStrings = [NSMutableArray arrayWithObject:path];
    if (embedded) [argvStrings addObject:@"--root-helper"];
    [argvStrings addObjectsFromArray:arguments ?: @[]];

    char **argv = calloc(argvStrings.count + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argvStrings.count; i++) argv[i] = strdup(argvStrings[i].UTF8String);
    argv[argvStrings.count] = NULL;

    int pipefd[2] = {-1,-1};
    if (pipe(pipefd) != 0) {
        if (output) *output = [NSString stringWithFormat:@"pipe failed: %d (%s)", errno, strerror(errno)];
        for (NSUInteger i = 0; i < argvStrings.count; i++) free(argv[i]);
        free(argv);
        return errno ?: -101;
    }

    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&actions, pipefd[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, pipefd[0]);

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    int p1 = posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    int p2 = posix_spawnattr_set_persona_uid_np(&attr, 0);
    int p3 = posix_spawnattr_set_persona_gid_np(&attr, 0);

    pid_t pid = 0;
    // Match TrollStore's spawnRoot behavior: do not inherit the app/jailbreak
    // environment into the privileged child process.
    int spawnResult = posix_spawn(&pid, path.fileSystemRepresentation, &actions, &attr, argv, NULL);
    close(pipefd[1]);

    NSMutableData *captured = [NSMutableData data];
    if (spawnResult == 0) {
        uint8_t buffer[1024];
        ssize_t n;
        while ((n = read(pipefd[0], buffer, sizeof(buffer))) > 0) [captured appendBytes:buffer length:(NSUInteger)n];
    }
    close(pipefd[0]);

    int status = 0;
    if (spawnResult == 0) waitpid(pid, &status, 0);

    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&actions);
    for (NSUInteger i = 0; i < argvStrings.count; i++) free(argv[i]);
    free(argv);

    NSString *text = [[NSString alloc] initWithData:captured encoding:NSUTF8StringEncoding] ?: @"";
    if (output) {
        if (text.length) {
            *output = text;
        } else if (spawnResult != 0) {
            *output = [NSString stringWithFormat:@"posix_spawn failed: %d (%s) | persona=%d uid=%d gid=%d | path=%@ | executable=%d",
                       spawnResult, strerror(spawnResult), p1, p2, p3, path,
                       [[NSFileManager defaultManager] isExecutableFileAtPath:path]];
        } else {
            *output = @"";
        }
    }

    if (spawnResult != 0) return spawnResult;
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return status;
}

int LTRunRootHelper(NSArray<NSString *> *arguments, NSString **output) {
    NSString *selfExe = [NSBundle mainBundle].executablePath;
    if (selfExe.length) {
        NSString *primary = nil;
        int rc = LTSpawnRootAtPath(selfExe, arguments, YES, &primary);
        if (rc == 0 || (rc != 202 && rc != 8 && rc != 85 && rc != 86 && rc != 88)) {
            if (output) *output = primary;
            return rc;
        }

        // Keep the external helper only as a fallback and diagnostic path.
        NSString *helper = [[NSBundle mainBundle] pathForResource:@"LiveTouchRootHelper" ofType:nil];
        if (helper.length) {
            NSString *fallback = nil;
            int frc = LTSpawnRootAtPath(helper, arguments, NO, &fallback);
            if (output) {
                *output = [NSString stringWithFormat:@"Embedded helper: %@\nLegacy helper: %@",
                           primary ?: @"(no output)", fallback ?: @"(no output)"];
            }
            return frc;
        }
        if (output) *output = primary;
        return rc;
    }

    if (output) *output = @"Main executable path is missing.";
    return -100;
}
