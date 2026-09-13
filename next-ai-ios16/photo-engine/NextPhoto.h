#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*NextPhotoProgress)(int step, int total, void *user);
typedef struct { double loadSeconds; double renderSeconds; } NextPhotoTiming;
int NextPhotoGenerate(const char *model, const char *prompt, const char *negative,
 int size, int steps, int turbo, int64_t seed, const char *destination,
 NextPhotoTiming *timing, NextPhotoProgress progress, void *user, char *error, int errorCapacity);
#ifdef __cplusplus
}
#endif

