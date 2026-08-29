static void format_bytes(unsigned long long bytes, char *out, size_t size)
{
    static const char *const units[] = {"B", "KB", "MB", "GB", "TB", "PB", "EB"};
    double value = (double)bytes;
    size_t unit = 0;
    while (value >= 1024.0 && unit + 1 < sizeof(units) / sizeof(units[0])) {
        value /= 1024.0;
        unit++;
    }
    if (unit == 0) snprintf(out, size, "%lluB", bytes);
    else if (value < 10.0) snprintf(out, size, "%.2f%s", value, units[unit]);
    else if (value < 100.0) snprintf(out, size, "%.1f%s", value, units[unit]);
    else snprintf(out, size, "%.0f%s", value, units[unit]);
}

static const char *mode_name(const char *mode)
{
    if (!strcmp(mode, "rule")) return "规则";
    if (!strcmp(mode, "global")) return "全局";
    if (!strcmp(mode, "direct")) return "直连";
    return "未知";
}

static void set_checked(lv_obj_t *button, int checked)
{
    if (!button) return;
    if (checked) lv_obj_add_state_p(button, LV_STATE_CHECKED);
    else lv_obj_clear_state_p(button, LV_STATE_CHECKED);
}

static void set_mode_selected(lv_obj_t *button, lv_obj_t *label, int selected)
{
    set_checked(button, selected);
    set_text_color(label, selected ? COLOR_TEXT : COLOR_MUTED);
}

static void set_status_color(uint32_t color)
{
    set_bg_color(status_indicator, color, 0);
    set_border_color(status_indicator, color, 0);
    set_shadow_color(status_indicator, color);
}

static void refresh_ui(void)
{
    struct mihomo_status status;
    char message[160], text[192], rr[32], tr[32], rt[32], tt[32];
    int generation, action_running;
    uint32_t status_color;
    if (!manager_page) return;
    pthread_mutex_lock(&shared_lock);
    generation = shared_generation;
    if (generation == ui_generation) { pthread_mutex_unlock(&shared_lock); return; }
    status = shared_status;
    safe_copy(message, sizeof(message),
              shared_message_page == PAGE_MIHOMO ? shared_message : "");
    action_running = action_is_mihomo(shared_action_running ?
                                      shared_running_action : shared_action);
    pthread_mutex_unlock(&shared_lock);
    ui_generation = generation; ui_status = status;
    if (!status.valid) {
        set_text_color(status_label, COLOR_MUTED);
        set_status_color(COLOR_MUTED);
        lv_label_set_text_p(status_label, "状态读取中…");
        lv_label_set_text_p(status_mode_label, "模式未知");
        lv_label_set_text_p(version_label, "未知");
        lv_label_set_text_p(memory_label, "--");
        lv_label_set_text_p(transparent_value_label, "未知");
        lv_label_set_text_p(dhcp_value_label, "未知");
        set_traffic_value(&traffic_rate_down, "--");
        set_traffic_value(&traffic_rate_up, "--");
        set_traffic_value(&traffic_total_down, "--");
        set_traffic_value(&traffic_total_up, "--");
        lv_label_set_text_p(updated_label, "--:--:--");
        return;
    }
    if (status.stale) {
        status_color = COLOR_AMBER;
        snprintf(text, sizeof(text), "数据延迟");
    } else if (!status.service_enabled) {
        status_color = COLOR_RED;
        snprintf(text, sizeof(text), "已禁用");
    } else if (status.start_pending) {
        status_color = COLOR_AMBER;
        snprintf(text, sizeof(text), "等待启动");
    } else if (!status.service_running) {
        status_color = COLOR_RED;
        snprintf(text, sizeof(text), "服务异常");
    } else if (!status.controller_listening) {
        status_color = COLOR_AMBER;
        snprintf(text, sizeof(text), "启动中");
    } else {
        status_color = COLOR_GREEN;
        snprintf(text, sizeof(text), "运行正常");
    }
    set_text_color(status_label, COLOR_TEXT);
    set_status_color(status_color);
    lv_label_set_text_p(status_label, text);
    if (!status.service_enabled) snprintf(text, sizeof(text), "服务关闭");
    else snprintf(text, sizeof(text), "%s模式", mode_name(status.proxy_mode));
    lv_label_set_text_p(status_mode_label, text);
    lv_label_set_text_p(version_label, status.version);
    lv_label_set_text_p(transparent_value_label,
                        status.transparent_enabled ? (status.service_running ? "已开启" : "已配置") : "已关闭");
    lv_label_set_text_p(dhcp_value_label,
                        status.dhcp_enabled ? "已接管" : "设备默认");
    if (status.service_running && status.rss_kb > 0) {
        snprintf(text, sizeof(text), "%.1f MB", (double)status.rss_kb/1024.0);
        lv_label_set_text_p(memory_label, text);
        format_bytes(status.rx_rate, rr, sizeof(rr)); format_bytes(status.tx_rate, tr, sizeof(tr));
        format_bytes(status.rx_bytes, rt, sizeof(rt)); format_bytes(status.tx_bytes, tt, sizeof(tt));
        snprintf(text, sizeof(text), "%s/s", rr);
        set_traffic_value(&traffic_rate_down, text);
        snprintf(text, sizeof(text), "%s/s", tr);
        set_traffic_value(&traffic_rate_up, text);
        set_traffic_value(&traffic_total_down, rt);
        set_traffic_value(&traffic_total_up, tt);
    } else {
        lv_label_set_text_p(memory_label, "--");
        set_traffic_value(&traffic_rate_down, "--");
        set_traffic_value(&traffic_rate_up, "--");
        set_traffic_value(&traffic_total_down, "--");
        set_traffic_value(&traffic_total_up, "--");
    }
    lv_label_set_text_p(service_button_label, status.service_enabled ? "禁用服务" : "启用服务");
    lv_label_set_text_p(transparent_button_label, status.transparent_enabled ? "透明代理：开" : "透明代理：关");
    center_button_label(service_button_label);
    center_button_label(transparent_button_label);
    set_checked(service_button, status.service_enabled); set_checked(transparent_button, status.transparent_enabled);
    set_mode_selected(mode_rule_button, mode_rule_label, !strcmp(status.proxy_mode, "rule"));
    set_mode_selected(mode_global_button, mode_global_label, !strcmp(status.proxy_mode, "global"));
    set_mode_selected(mode_direct_button, mode_direct_label, !strcmp(status.proxy_mode, "direct"));
    lv_label_set_text_p(message_label, message[0] ? message : (action_running ? "正在执行，请稍候…" : ""));
    lv_label_set_text_p(updated_label, status.updated);
}
