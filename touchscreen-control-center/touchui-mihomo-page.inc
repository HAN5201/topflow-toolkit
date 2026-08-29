static int create_mihomo_page(lv_obj_t *top)
{
    lv_obj_t *title_label, *section_label;
    lv_obj_t *divider, *mode_segment;
    if (!page_shell_init(&mihomo_shell, top, PAGE_MIHOMO, "Mihomo",
                         feature_back_clicked)) return 0;
    manager_page = mihomo_shell.root;

    make_panel(manager_page, 8, 48, 304, 117, COLOR_CARD);
    make_panel(manager_page, 8, 168, 304, 59, COLOR_CARD_ALT);
    make_panel(manager_page, 8, 284, 304, 82, COLOR_CARD);

    status_indicator = lv_obj_create_p(manager_page);
    if (status_indicator) {
        lv_obj_set_size_p(status_indicator, 9, 9);
        lv_obj_set_pos_p(status_indicator, 16,
                         center_marker_on_text_line(58, ui_font, 9));
        lv_obj_clear_flag_p(status_indicator, LV_OBJ_FLAG_SCROLLABLE);
        style_surface(status_indicator, COLOR_MUTED, COLOR_MUTED, 9, 0);
        if (lv_obj_set_style_shadow_width_p)
            lv_obj_set_style_shadow_width_p(status_indicator, 8, 0);
        set_shadow_color(status_indicator, COLOR_MUTED);
        if (lv_obj_set_style_shadow_opa_p)
            lv_obj_set_style_shadow_opa_p(status_indicator, 31, 0);
    }
    status_label = make_single_line_label(manager_page, "状态读取中…", 32, 58, 168, 25);
    set_text_color(status_label, COLOR_MUTED);
    status_mode_label = make_single_line_label(manager_page, "模式未知", 228, 58, 76, 25);
    set_text_color(status_mode_label, COLOR_MUTED);
    divider = lv_obj_create_p(manager_page);
    if (divider) {
        lv_obj_set_size_p(divider, 288, 1);
        lv_obj_set_pos_p(divider, 16, 88);
        lv_obj_clear_flag_p(divider, LV_OBJ_FLAG_SCROLLABLE);
        style_surface(divider, COLOR_BORDER, COLOR_BORDER, 0, 0);
    }
    title_label = make_single_line_label(manager_page, "核心", 16, 97, 42, 24);
    set_text_color(title_label, COLOR_MUTED);
    version_label = make_single_line_label(manager_page, "未知", 62, 97, 84, 24);
    title_label = make_single_line_label(manager_page, "内存", 164, 97, 42, 24);
    set_text_color(title_label, COLOR_MUTED);
    memory_label = make_single_line_label(manager_page, "--", 208, 97, 96, 24);
    title_label = make_single_line_label(manager_page, "透明代理", 16, 128, 72, 24);
    set_text_color(title_label, COLOR_MUTED);
    transparent_value_label = make_single_line_label(manager_page, "未知", 91, 128, 57, 24);
    title_label = make_single_line_label(manager_page, "DHCP", 164, 128, 50, 24);
    set_text_color(title_label, COLOR_MUTED);
    dhcp_value_label = make_single_line_label(manager_page, "未知", 217, 128, 87, 24);

    title_label = make_single_line_label(manager_page, "流量", 16, 184, 42, 24);
    set_text_color(title_label, COLOR_TEXT);
    title_label = make_single_line_label(manager_page, "实时", 65, 171, 42, 24);
    set_text_color(title_label, COLOR_MUTED);
    traffic_rate_down = make_download_value(manager_page, 108, 171,
                                            69, ui_font_small);
    traffic_rate_up = make_upload_value(manager_page, 198, 171,
                                        89, ui_font_small);
    title_label = make_single_line_label(manager_page, "累计", 65, 198, 42, 24);
    set_text_color(title_label, COLOR_MUTED);
    traffic_total_down = make_download_value(manager_page, 108, 198,
                                             69, ui_font_small);
    traffic_total_up = make_upload_value(manager_page, 198, 198,
                                         89, ui_font_small);
    service_button = make_button(manager_page, "启用服务", 14, 235, 142, 44, service_clicked, &service_button_label);
    transparent_button = make_button(manager_page, "透明代理：关", 164, 235, 142, 44, transparent_clicked, &transparent_button_label);
    style_button(service_button, COLOR_BUTTON, COLOR_BUTTON_PRESSED,
                 COLOR_BUTTON_PRESSED, COLOR_ACCENT_SOFT);
    style_button(transparent_button, COLOR_BUTTON, COLOR_BUTTON_PRESSED,
                 COLOR_BUTTON_PRESSED, COLOR_ACCENT_SOFT);
    section_label = make_single_line_label(manager_page, "代理模式", 16, 290, 288, 24);
    set_text_color(section_label, COLOR_MUTED);
    mode_segment = make_panel(manager_page, 14, 315, 292, 46, COLOR_SEGMENT);
    if (mode_segment) style_surface(mode_segment, COLOR_SEGMENT, COLOR_SEGMENT, 10, 0);
    mode_rule_button = make_button(manager_page, "规则", 18, 319, 92, 38,
                                   mode_rule_clicked, &mode_rule_label);
    mode_global_button = make_button(manager_page, "全局", 114, 319, 92, 38,
                                     mode_global_clicked, &mode_global_label);
    mode_direct_button = make_button(manager_page, "直连", 210, 319, 92, 38,
                                     mode_direct_clicked, &mode_direct_label);
    style_segment_button(mode_rule_button);
    style_segment_button(mode_global_button);
    style_segment_button(mode_direct_button);
    set_text_color(mode_rule_label, COLOR_MUTED);
    set_text_color(mode_global_label, COLOR_MUTED);
    set_text_color(mode_direct_label, COLOR_MUTED);
    message_label = make_label(manager_page, "", 14, 376, 292, 48);
    set_text_color(message_label, COLOR_MESSAGE);
    updated_label = mihomo_shell.clock_label;

    return create_confirmation_overlay(manager_page);
}

static void request_mihomo_page(void)
{
    pending_mihomo_open = 1;
}

static void destroy_mihomo_page(void)
{
    if (manager_page && lv_obj_del_p) lv_obj_del_p(manager_page);
    manager_page = NULL;
    memset(&mihomo_shell, 0, sizeof(mihomo_shell));
    confirm_scrim = NULL;
    confirm_panel = NULL;
    confirm_text_label = NULL;
    confirm_action = ACTION_NONE;
    status_indicator = NULL;
    status_label = NULL;
    status_mode_label = NULL;
    version_label = NULL;
    memory_label = NULL;
    transparent_value_label = NULL;
    dhcp_value_label = NULL;
    message_label = NULL;
    updated_label = NULL;
    service_button = NULL;
    service_button_label = NULL;
    transparent_button = NULL;
    transparent_button_label = NULL;
    mode_rule_button = NULL;
    mode_global_button = NULL;
    mode_direct_button = NULL;
    mode_rule_label = NULL;
    mode_global_label = NULL;
    mode_direct_label = NULL;
    memset(&traffic_rate_down, 0, sizeof(traffic_rate_down));
    memset(&traffic_rate_up, 0, sizeof(traffic_rate_up));
    memset(&traffic_total_down, 0, sizeof(traffic_total_down));
    memset(&traffic_total_up, 0, sizeof(traffic_total_up));
}
