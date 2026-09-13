#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*NextPhotoProgress)(int step, int total, void *user);
int NextPhotoGenerate(const char *model, const char *prompt, const char *negative,
 int size, int steps, int64_t seed, const char *destination,
 NextPhotoProgress progress, void *user, char *error, int errorCapacity);
#ifdef __cplusplus
}
#endif
