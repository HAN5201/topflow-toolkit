#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define NETWORK_MODEM_COUNT 3

struct modem_status {
    char target_status[3][16];
};

#include "../touchui-json.inc"

static void assert_storage(const char *state)
{
    char runtime[8192], storage[1024];

    assert(json_object(state, "runtime", runtime, sizeof(runtime)));
    assert(json_object(runtime, "storage", storage, sizeof(storage)));
    assert(json_ull(storage, "total", 0) > 0);
    assert(json_ull(storage, "used", 0) > 0);
    assert(json_ull(storage, "available", 0) > 0);
}

int main(void)
{
    const char *state =
        "{\"aggregation\":{\"server\":{\"source\":\"runtime\"}},"
        "\"runtime\" : {\"storage\":{\"total\":4096,"
        "\"used\":1024,\"available\":3072}}}";

    assert_storage(state);
    puts("json-key-match: ok");
    return 0;
}
