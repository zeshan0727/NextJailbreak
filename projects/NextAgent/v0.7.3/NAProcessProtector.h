#pragma once
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

char *NAProtectProcessJSON(pid_t pid, int *ok);
char *NAUnprotectProcessJSON(pid_t pid, int *ok);
char *NAProtectionStatusJSON(int *ok);

#ifdef __cplusplus
}
#endif
