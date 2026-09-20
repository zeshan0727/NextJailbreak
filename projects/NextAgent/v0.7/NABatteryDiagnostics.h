#pragma once
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

char *NABatteryPropertiesJSON(int *ok);
char *NAReadBatteryPlistJSON(const char *path, int *ok);

#ifdef __cplusplus
}
#endif
