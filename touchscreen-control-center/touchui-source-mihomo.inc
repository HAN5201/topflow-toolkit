static int read_counter(const char *path, unsigned long long *value)
{
    FILE *file = fopen(path, "r");
    int ok;
    if (!file) return 0;
    ok = fscanf(file, "%llu", value) == 1;
    fclose(file);
    return ok;
}
static void extract_version(const char *line, char *out, size_t size)
{
    const char *start = strstr(line, " v");
    size_t length = 0;
    start = start ? start + 1 : line;
    while (start[length] && start[length] != ' ' && length + 1 < size) length++;
    if (!length) { safe_copy(out, size, "未知"); return; }
    memcpy(out, start, length);
    out[length] = '\0';
}

static int collect_manager_status(struct mihomo_status *status)
{
    char json[4096], version_line[192];
    memset(status, 0, sizeof(*status));
    safe_copy(status->proxy_mode, sizeof(status->proxy_mode), "unknown");
    safe_copy(status->version, sizeof(status->version), "未知");
    if (run_manager(json, sizeof(json), "status", NULL) != 0 || !json_bool(json, "ok", 0)) return 0;
    status->service_enabled = json_bool(json, "service_enabled", 0);
    status->service_running = json_bool(json, "service_running", 0);
    status->start_pending = json_bool(json, "start_pending", 0);
    status->transparent_enabled = json_bool(json, "transparent_enabled", 0);
    status->dhcp_enabled = json_bool(json, "dhcp_enabled", 0);
    status->controller_listening = json_bool(json, "controller_listening", 0);
    status->rss_kb = json_long(json, "rss_kb", 0);
    json_string(json, "proxy_mode", status->proxy_mode, sizeof(status->proxy_mode));
    if (json_string(json, "version", version_line, sizeof(version_line)))
        extract_version(version_line, status->version, sizeof(status->version));
    status->valid = 1;
    return 1;
}
