#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TIME_GENOFF_LIBRARY "/usr/lib/libtime_genoff.so.1"
#define PERSISTENT_TIME_BASE 12
#define MIN_TRUSTED_EPOCH UINT64_C(1767225600)
#define MAX_TRUSTED_EPOCH UINT64_C(4102444800)

enum time_unit {
    TIME_STAMP = 0,
    TIME_MSEC = 1,
    TIME_SECS = 2,
    TIME_JULIAN = 3,
};

enum time_genoff_operation {
    T_SET = 0,
    T_GET = 1,
};

struct time_genoff_info {
    int base;
    void *ts_val;
    int unit;
    int operation;
};

typedef int (*time_genoff_operation_fn)(struct time_genoff_info *info);

static void usage(const char *program)
{
    fprintf(stderr,
            "usage: %s get\n"
            "       %s set <unix-seconds>\n",
            program, program);
}
static int parse_epoch(const char *text, uint64_t *epoch)
{
    char *end = NULL;
    unsigned long long value;

    errno = 0;
    value = strtoull(text, &end, 10);
    if (errno != 0 || end == text || *end != '\0' ||
        value < MIN_TRUSTED_EPOCH || value > MAX_TRUSTED_EPOCH)
        return -1;
    *epoch = (uint64_t)value;
    return 0;
}

int main(int argc, char **argv)
{
    struct time_genoff_info info;
    time_genoff_operation_fn operation;
    uint64_t value = 0;
    void *handle;
    int result;

    if (argc != 2 && argc != 3) {
        usage(argv[0]);
        return 2;
    }

    memset(&info, 0, sizeof(info));
    info.base = PERSISTENT_TIME_BASE;
    info.ts_val = &value;
    info.unit = TIME_SECS;

    if (strcmp(argv[1], "get") == 0 && argc == 2) {
        info.operation = T_GET;
    } else if (strcmp(argv[1], "set") == 0 && argc == 3) {
        if (parse_epoch(argv[2], &value) != 0) {
            fprintf(stderr, "refusing untrusted epoch: %s\n", argv[2]);
            return 2;
        }
        info.operation = T_SET;
    } else {
        usage(argv[0]);
        return 2;
    }

    handle = dlopen(TIME_GENOFF_LIBRARY, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        fprintf(stderr, "cannot load %s: %s\n", TIME_GENOFF_LIBRARY, dlerror());
        return 1;
    }

    dlerror();
    *(void **)(&operation) = dlsym(handle, "time_genoff_operation");
    if (operation == NULL) {
        const char *error = dlerror();
        fprintf(stderr, "cannot resolve time_genoff_operation: %s\n",
                error != NULL ? error : "unknown error");
        dlclose(handle);
        return 1;
    }

    result = operation(&info);
    if (result != 0) {
        fprintf(stderr, "time_genoff operation failed: base=%d result=%d\n",
                PERSISTENT_TIME_BASE, result);
        dlclose(handle);
        return 1;
    }

    printf("base=%d epoch=%llu\n", PERSISTENT_TIME_BASE,
           (unsigned long long)value);
    dlclose(handle);
    return 0;
}
