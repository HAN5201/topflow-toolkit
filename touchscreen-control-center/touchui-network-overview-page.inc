static int create_network_page(lv_obj_t *top)
{
    static void (*open_callbacks[NETWORK_MODEM_COUNT])(void *) = {
        open_network_detail_5g, open_network_detail_4g1, open_network_detail_4g2
    };
    network_parent = top;
    if (!page_shell_init(&network_shell, top, PAGE_NETWORK, "网络仪表",
                         feature_back_clicked)) return 0;
    network_page = network_shell.root;

    for (int i = 0; i < NETWORK_MODEM_COUNT; i++) {
        int y = 50 + i * 128;
        make_panel(network_page, 8, y, 304, 120, COLOR_CARD);
        network_dot[i] = lv_obj_create_p(network_page);
        if (network_dot[i]) {
            lv_obj_set_size_p(network_dot[i], 8, 8);
            lv_obj_set_pos_p(network_dot[i], 18,
                             center_marker_on_text_line(y + 8,
                                                        ui_font_small, 8));
            lv_obj_clear_flag_p(network_dot[i], LV_OBJ_FLAG_SCROLLABLE);
            style_surface(network_dot[i], COLOR_MUTED, COLOR_MUTED, 8, 0);
        }
        network_header_label[i] = make_detail_label(network_page,
            network_module_titles[i], 36, y + 8, 158, 22, ui_font_small, COLOR_TEXT);
        network_summary_label[i] = make_scrolling_detail_label(network_page, "读取中…",
            196, y + 10, 76, 18, ui_font_tiny, COLOR_MUTED, 1);
        network_signal_icon[i] = make_stock_signal_icon(network_page, 282, y + 8);
        network_signal_label[i] = make_scrolling_detail_label(network_page, "-- · --",
            18, y + 98, 116, 18, ui_font_tiny, COLOR_MUTED, 0);
        make_network_rule(network_page, 18, y + 37, 284, 1);
        network_traffic_label[i] = make_detail_label(network_page, "-- dBm",
            18, y + 44, 130, 31, ui_font_large, COLOR_TEXT);
        network_rsrp_caption[i] = make_detail_label(network_page, "RSRP",
            18, y + 75, 80, 18, ui_font_tiny, COLOR_MUTED);
        network_snr_label[i] = make_detail_label(network_page, "-- dB",
            171, y + 44, 121, 31, ui_font_large, COLOR_TEXT);
        network_snr_caption[i] = make_detail_label(network_page, "SNR",
            171, y + 75, 80, 18, ui_font_tiny, COLOR_MUTED);
        network_down[i] = make_download_value(network_page, 164, y + 96,
                                               52, ui_font_small);
        network_up[i] = make_upload_value(network_page, 238, y + 96,
                                           48, ui_font_small);
        make_click_layer(network_page, 8, y, 304, 120, open_callbacks[i]);
    }
    network_updated_label = network_shell.clock_label;
    return 1;
}
