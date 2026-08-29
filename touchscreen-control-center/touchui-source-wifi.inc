static int collect_wifi_power_status(struct wifi_power_status *status)
{
    static const char payload[] =
        "{\"action\":\"wifi.txpower.status\",\"params\":{}}";
    static const char *keys[2] = {"2g", "5g"};
    char response[4096], result[2048], band[1024];
    if (!status) return 0;
    memset(status, 0, sizeof(*status));
    if (!post_datad_control(payload, response, sizeof(response)) ||
        !json_bool(response, "ok", 0) ||
        !json_object(response, "result", result, sizeof(result))) return 0;
    for (int i = 0; i < 2; i++) {
        struct wifi_power_band_status *item = &status->bands[i];
        if (!json_object(result, keys[i], band, sizeof(band))) return 0;
        item->enabled = json_bool(band, "enabled", 0);
        item->percent = (int)json_long(band, "percent", -1);
        item->txpower_dbm = (int)json_long(band, "txpower_dbm", -1);
        item->limit_dbm = (int)json_long(band, "limit_dbm", -1);
        item->factory_limit_dbm = (int)json_long(band, "factory_limit_dbm", -1);
        if (item->percent < 10 || item->percent > 100 ||
            item->txpower_dbm < 1 || item->txpower_dbm > 30 ||
            item->limit_dbm < 1 || item->limit_dbm > 30 ||
            item->factory_limit_dbm < 1 || item->factory_limit_dbm > 30)
            return 0;
        item->valid = 1;
    }
    status->valid = 1;
    return 1;
}
