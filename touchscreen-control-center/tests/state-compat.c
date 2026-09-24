/* Exercise the same collectors as the touchscreen against a snapshot or device. */
#include <assert.h>
#include "../touchui-hook.c"

static int address_label_token;
static char address_diagnostic[96];

static void capture_diagnostic(lv_obj_t *obj, const char *text)
{
    if (obj == (lv_obj_t *)&address_label_token)
        safe_copy(address_diagnostic, sizeof(address_diagnostic), text);
}

static const char *address_diagnostic_for(const struct network_status *status)
{
    ui_network_status = *status;
    diagnostics_page = (lv_obj_t *)&address_label_token;
    diagnostic_values[2] = (lv_obj_t *)&address_label_token;
    lv_label_set_text_p = capture_diagnostic;
    refresh_diagnostics_ui();
    return address_diagnostic;
}

static void check_interfaces(const char *interfaces, const char *ipv4,
                             long mask4, const char *ipv6, long mask6,
                             int expected_ok)
{
    char state[8192];
    struct network_status status = {0};
    snprintf(state, sizeof(state), "{\"modems\":[{\"id\":\"x75\","
             "\"net\":{\"type\":\"LTE\"},\"interfaces\":%s}]}", interfaces);
    assert(collect_modem_status(state, 0, &status.modems[0]));
    assert(!strcmp(status.modems[0].ipv4_address, ipv4));
    assert(status.modems[0].ipv4_mask == mask4);
    assert(!strcmp(status.modems[0].ipv6_address, ipv6));
    assert(status.modems[0].ipv6_mask == mask6);
    status.modems[1] = status.modems[2] = status.modems[0];
    assert(!strcmp(address_diagnostic_for(&status), expected_ok ?
                   "IPv4 与 DNS 正常" : "地址或 DNS 缺失"));
}

static void test_interface_contract(void)
{
    /* Current datad schema, reordered members, and a same-name decoy. */
    check_interfaces(
        "{\"ipv6\":{\"dns\":[\"2001:db8::53\"],\"up\":true,"
        "\"ipv6\":[{\"mask\":64,\"address\":\"2001:db8::2\"}],\"ipv4\":[]},"
        "\"ipv4\":{\"debug\":{\"address\":\"decoy\",\"mask\":1},"
        "\"ipv6\":[],\"ipv4\":[{\"mask\":24,\"address\":\"192.0.2.2\"}],"
        "\"dns\":[\"192.0.2.53\"],\"up\":true}}",
        "192.0.2.2", 24, "2001:db8::2", 64, 1);
    /* Legacy flat members still work; keep address and prefix paired. */
    check_interfaces(
        "{\"ipv4\":{\"up\":true,\"address\":\"192.0.2.3\",\"mask\":25,"
        "\"dns\":[\"192.0.2.53\"]},\"ipv6\":{\"address\":\"2001:db8::3\",\"mask\":56}}",
        "192.0.2.3", 25, "2001:db8::3", 56, 1);
    /* Empty lists must not fall back to stale flat or other-family data. */
    check_interfaces(
        "{\"ipv4\":{\"up\":true,\"address\":\"192.0.2.9\",\"mask\":24,"
        "\"ipv4\":[],\"ipv6\":[{\"address\":\"2001:db8::9\",\"mask\":64}],"
        "\"dns\":[\"192.0.2.53\"]}}", "", 0, "", 0, 0);
    /* Ignore empty entries; select the first nonempty entry, including /0. */
    check_interfaces(
        "{\"ipv4\":{\"up\":true,\"dns\":[\"192.0.2.53\"],"
        "\"ipv4\":[{\"address\":\"\",\"mask\":20}, {\"address\":\"192.0.2.4\",\"mask\":0},"
        "{\"address\":\"192.0.2.5\",\"mask\":24}]}}", "192.0.2.4", 0, "", 0, 1);
    /* A real missing DNS or down interface must continue to warn. */
    check_interfaces(
        "{\"ipv4\":{\"up\":true,\"ipv4\":[{\"address\":\"192.0.2.6\",\"mask\":24}],"
        "\"dns\":[]}}", "192.0.2.6", 24, "", 0, 0);
    check_interfaces(
        "{\"ipv4\":{\"up\":false,\"ipv4\":[{\"address\":\"192.0.2.7\",\"mask\":24}],"
        "\"dns\":[\"192.0.2.53\"]}}", "192.0.2.7", 24, "", 0, 0);
    puts("interface-contract: 6 collector-to-diagnostic cases passed");
}

int main(int argc, char **argv)
{
    char *state = malloc(NETWORK_HTTP_MAX);
    char modem[16384];
    struct network_status status;
    int found = 0;
    assert(state);
    if (argc == 1) {
        test_interface_contract();
        free(state);
        return 0;
    }
    assert(argc == 2);
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
    printf("address_diagnostic=%s\n", address_diagnostic_for(&status));
    for (int i = 0; i < NETWORK_MODEM_COUNT; i++)
        printf("modem_index=%d ipv4_up=%d address_present=%d dns_present=%d ipv6_address_present=%d\n",
               i, status.modems[i].ipv4_up, !!status.modems[i].ipv4_address[0],
               !!status.modems[i].ipv4_dns[0], !!status.modems[i].ipv6_address[0]);
    free(state);
    return 0;
}
