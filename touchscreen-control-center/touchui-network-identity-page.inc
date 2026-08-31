static int create_network_identity_page(lv_obj_t *top)
{
    static const char *sim_keys[6] = {
        "类型", "状态", "号码", "ICCID", "IMSI", "IMEI"
    };
    static const char *module_keys[7] = {
        "模块", "数据接口", "逻辑 WAN", "传输", "USB", "调试", "序列"
    };
    trace_ui_create("identity-begin");
    if (!page_shell_init(&network_identity_shell, top, PAGE_NETWORK_IDENTITY,
                         "X75(5G)", network_identity_back_clicked)) return 0;
    trace_ui_create("identity-shell");
    network_identity_page = network_identity_shell.root;

    make_panel(network_identity_page, 8, 48, 304, 172, COLOR_CARD);
    make_detail_label(network_identity_page, "SIM 身份", 20, 58, 100, 17,
                      ui_font_tiny, COLOR_MUTED);
    for (int i = 0; i < 6; i++) {
        make_detail_label(network_identity_page, sim_keys[i],
                          18, 82 + i * 21, 58, 17,
                          ui_font_tiny, COLOR_MUTED);
        network_identity_sim_values[i] = make_scrolling_detail_label(
                          network_identity_page, "--",
                          78, 82 + i * 21, 224, 17,
                          ui_font_tiny, COLOR_TEXT, 1);
    }
    trace_ui_create("identity-sim");

    make_panel(network_identity_page, 8, 228, 304, 207, COLOR_CARD);
    make_detail_label(network_identity_page, "模块", 20, 238, 100, 17,
                      ui_font_tiny, COLOR_MUTED);
    for (int i = 0; i < 7; i++) {
        make_detail_label(network_identity_page, module_keys[i],
                          18, 263 + i * 23, 68, 17,
                          ui_font_tiny, COLOR_MUTED);
        network_identity_module_values[i] = make_scrolling_detail_label(
                          network_identity_page, "--",
                          88, 263 + i * 23, 214, 17,
                          ui_font_tiny, COLOR_TEXT, 1);
    }
    for (int i = 0; i < 6; i++) {
        if (!network_identity_sim_values[i]) {
            trace_ui_create("identity-allocation-failed");
            return 0;
        }
    }
    for (int i = 0; i < 7; i++) {
        if (!network_identity_module_values[i]) {
            trace_ui_create("identity-allocation-failed");
            return 0;
        }
    }
    trace_ui_create("identity-complete");
    return 1;
}
