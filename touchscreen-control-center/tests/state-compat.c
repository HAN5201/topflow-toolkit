/* Exercise the same collectors as the touchscreen against a snapshot or device. */
#include <assert.h>
#include "../touchui-hook.c"

int main(int argc, char **argv)
{
    char *state = malloc(NETWORK_HTTP_MAX);
    char modem[16384];
    struct network_status status;
    int found = 0;
    assert(state && argc == 2);
    if (!strcmp(argv[1], "--live")) {
        assert(collect_network_status(&status, state, NETWORK_HTTP_MAX));
    } else {
        FILE *file = fopen(argv[1], "rb");
        size_t length;
        assert(file);
        length = fread(state, 1, NETWORK_HTTP_MAX - 1, file);
        assert(feof(file) && length > 0);
        fclose(file);
        state[length] = '\0';
        memset(&status, 0, sizeof(status));
        assert(collect_device_status(state, &status.device));
        for (int i = 0; i < NETWORK_MODEM_COUNT; i++)
            collect_modem_status(state, i, &status.modems[i]);
    }
    for (int i = 0; i < NETWORK_MODEM_COUNT; i++) {
        assert(modem_json_object(state, i, modem, sizeof(modem)));
        if (status.modems[i].valid) found++;
    }
    assert(status.device.valid);
    assert(status.device.storage_total > 0 && status.device.mem_total > 0);
    printf("state-compat: parsed_modems=3 registered_modems=%d device_valid=%d storage_valid=1 memory_valid=1\n",
           found, status.device.valid);
    free(state);
    return 0;
}
