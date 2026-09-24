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

int main(int argc, char **argv)
{
    char object[16384], id[32];
    const char *reordered =
        "{\"traffic\":{\"rx_bytes\":99},\"modems\":["
        "{\"net\":{\"id\":\"decoy\"},\"role\":\"external_4g\",\"id\":\"v3e2\"},"
        "{\"debug\":{},\"id\" : \"v3e1\",\"role\":\"external_4g\"},"
        "{\"id\":\"x75\",\"net\":{},\"role\":\"integrated_5g\"}]}";
    const char *state =
        "{\"aggregation\":{\"server\":{\"source\":\"runtime\"}},"
        "\"runtime\" : {\"storage\":{\"total\":1947254784,"
        "\"used\":133091328,\"available\":1797386240}}}";
    FILE *file;
    char *input;
    long length;

    assert_storage(state);
    for (int i = 0; i < 3; i++) {
        static const char *ids[] = {"x75", "v3e1", "v3e2"};
        assert(modem_json_object(reordered, i, object, sizeof(object)));
        assert(json_string(object, "id", id, sizeof(id)));
        assert(!strcmp(id, ids[i]));
    }
    assert(!modem_json_object("{\"modems\":[]}", 0, object, sizeof(object)));
    assert(json_object_by_id(reordered, "v3e2", object, sizeof(object)));
    assert(json_string(object, "id", id, sizeof(id)) && !strcmp(id, "v3e2"));
    assert(json_long("{\"nested\":{\"value\":3},\"value\":7}", "value", 0) == 7);
    assert(json_long("{\"nested\":{\"value\":3}}", "value", 9) == 9);
    if (argc == 2) {
        file = fopen(argv[1], "rb");
        assert(file);
        assert(fseek(file, 0, SEEK_END) == 0);
        length = ftell(file);
        assert(length > 0);
        rewind(file);
        input = malloc((size_t)length + 1);
        assert(input);
        assert(fread(input, 1, (size_t)length, file) == (size_t)length);
        input[length] = '\0';
        fclose(file);
        assert_storage(input);
        for (int i = 0; i < 3; i++)
            assert(modem_json_object(input, i, object, sizeof(object)));
        free(input);
    }
    puts("json-key-match: ok");
    return 0;
}
