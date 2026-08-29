static long long monotonic_millis(void)
{
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (long long)now.tv_sec * 1000LL + now.tv_nsec / 1000000LL;
}

static int read_mihomo_rss(long *rss_kb)
{
    FILE *file;
    char path[64], line[160];
    long pid, value;
    if (!rss_kb) return 0;
    file = fopen(MIHOMO_PIDFILE, "r");
    if (!file) return 0;
    if (fscanf(file, "%ld", &pid) != 1 || pid <= 1) {
        fclose(file);
        return 0;
    }
    fclose(file);
    snprintf(path, sizeof(path), "/proc/%ld/status", pid);
    file = fopen(path, "r");
    if (!file) return 0;
    while (fgets(line, sizeof(line), file)) {
        if (sscanf(line, "VmRSS: %ld kB", &value) == 1) {
            fclose(file);
            *rss_kb = value;
            return 1;
        }
    }
    fclose(file);
    return 0;
}

static void update_fast_status(struct mihomo_status *status,
                               unsigned long long *old_rx, unsigned long long *old_tx,
                               struct timespec *old_time, int *old_valid)
{
    unsigned long long rx = 0, tx = 0;
    struct timespec now;
    struct tm local;
    double seconds;
    time_t wall;
    long rss_kb;
    if (!status || !status->valid) return;
    if (!status->service_running) status->rss_kb = 0;
    else if (read_mihomo_rss(&rss_kb)) status->rss_kb = rss_kb;
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (read_counter(TRAFFIC_RX, &rx) && read_counter(TRAFFIC_TX, &tx)) {
        status->rx_bytes = rx; status->tx_bytes = tx;
        if (*old_valid && rx >= *old_rx && tx >= *old_tx) {
            seconds = (double)(now.tv_sec - old_time->tv_sec) +
                      (double)(now.tv_nsec - old_time->tv_nsec) / 1000000000.0;
            if (seconds > 0.1) {
                status->rx_rate = (unsigned long long)((rx - *old_rx) / seconds);
                status->tx_rate = (unsigned long long)((tx - *old_tx) / seconds);
            }
        }
        *old_rx = rx; *old_tx = tx; *old_time = now; *old_valid = 1;
    } else *old_valid = 0;
    wall = time(NULL);
    localtime_r(&wall, &local);
    snprintf(status->updated, sizeof(status->updated), "%02d:%02d:%02d",
             local.tm_hour, local.tm_min, local.tm_sec);
}

static int action_is_mihomo(int action)
{
    return action >= ACTION_SERVICE_ENABLE && action <= ACTION_MODE_DIRECT;
}

static enum page_id message_page_for_action(int action)
{
    return action_is_mihomo(action) ? PAGE_MIHOMO : PAGE_DEVICE;
}

static enum page_id message_page_for_page(enum page_id page)
{
    if (page == PAGE_MIHOMO) return PAGE_MIHOMO;
    if (page == PAGE_DEVICE || page == PAGE_COOLING_CURVE ||
        page == PAGE_DIAGNOSTICS) return PAGE_DEVICE;
    return PAGE_STOCK;
}

static void publish_message(int action, int ok, const char *message)
{
    pthread_mutex_lock(&shared_lock);
    safe_copy(shared_message, sizeof(shared_message), message);
    shared_message_page = message_page_for_action(action);
    shared_generation++;
    pthread_mutex_unlock(&shared_lock);
    (void)ok;
}

static void execute_action(int action, int action_band,
                           int action_value, int action_value2,
                           const struct fan_curve_point_status *curve,
                           int curve_count)
{
    const char *arg1 = NULL, *arg2 = NULL;
    const char *control = NULL;
    char output[4096], message[160], control_buffer[1024];
    int ok;
    switch (action) {
    case ACTION_SERVICE_ENABLE: arg1 = "service-set"; arg2 = "true"; break;
    case ACTION_SERVICE_DISABLE: arg1 = "service-set"; arg2 = "false"; break;
    case ACTION_TRANSPARENT_ON: arg1 = "transparent-set"; arg2 = "true"; break;
    case ACTION_TRANSPARENT_OFF: arg1 = "transparent-set"; arg2 = "false"; break;
    case ACTION_MODE_RULE: arg1 = "proxy-mode-set"; arg2 = "rule"; break;
    case ACTION_MODE_GLOBAL: arg1 = "proxy-mode-set"; arg2 = "global"; break;
    case ACTION_MODE_DIRECT: arg1 = "proxy-mode-set"; arg2 = "direct"; break;
    case ACTION_FAN_FACTORY:
        control = "{\"action\":\"cooling.fan.set_mode\",\"params\":{\"mode\":\"automatic\"}}";
        break;
    case ACTION_FAN_CUSTOM:
        control = "{\"action\":\"cooling.fan.set_mode\",\"params\":{\"mode\":\"custom\"}}";
        break;
    case ACTION_FAN_ALWAYS:
        control = "{\"action\":\"cooling.fan.set_mode\",\"params\":{\"mode\":\"always_on\"}}";
        break;
    case ACTION_FAN_CURVE_APPLY: {
        size_t used = 0;
        int written;
        if (!curve || curve_count < 2 || curve_count > TOUCHUI_FAN_CURVE_MAX) return;
        written = snprintf(control_buffer, sizeof(control_buffer),
                           "{\"action\":\"cooling.fan.set_curve\",\"params\":{\"points\":[");
        if (written < 0 || (size_t)written >= sizeof(control_buffer)) return;
        used = (size_t)written;
        for (int i = 0; i < curve_count; i++) {
            written = snprintf(control_buffer + used, sizeof(control_buffer) - used,
                               "%s{\"temperature\":%d,\"pwm\":%d}", i ? "," : "",
                               curve[i].temperature, curve[i].pwm);
            if (written < 0 || (size_t)written >= sizeof(control_buffer) - used) return;
            used += (size_t)written;
        }
        written = snprintf(control_buffer + used, sizeof(control_buffer) - used, "]}}");
        if (written < 0 || (size_t)written >= sizeof(control_buffer) - used) return;
        control = control_buffer;
        break;
    }
    case ACTION_LIQUID_AUTO:
        control = "{\"action\":\"cooling.liquid.set_mode\",\"params\":{\"mode\":\"automatic\"}}";
        break;
    case ACTION_LIQUID_LOW:
        control = "{\"action\":\"cooling.liquid.set_mode\",\"params\":{\"mode\":\"low\"}}";
        break;
    case ACTION_LIQUID_HIGH:
        control = "{\"action\":\"cooling.liquid.set_mode\",\"params\":{\"mode\":\"high\"}}";
        break;
    case ACTION_WIFI_APPLY:
        if (action_band < 0 || action_band > 1 || action_value < 10 ||
            action_value > 100 || action_value % 10 ||
            action_value2 < 1 || action_value2 > 30) return;
        snprintf(control_buffer, sizeof(control_buffer),
                 "{\"action\":\"wifi.txpower.apply\",\"params\":{"
                 "\"band\":\"%s\",\"percent\":%d,\"limit_dbm\":%d}}",
                 action_band ? "5g" : "2g", action_value, action_value2);
        control = control_buffer;
        break;
    case ACTION_STATE_REFRESH:
        control = "{\"action\":\"state.refresh\",\"params\":{}}";
        break;
    default: return;
    }
    publish_message(action, 1, "正在执行，请稍候…");
    if (control) {
        if (!post_datad_control(control, output, sizeof(output))) {
            publish_message(action, 0, "设备控制接口执行失败"); return;
        }
    } else if (run_manager(output, sizeof(output), arg1, arg2) != 0) {
        publish_message(action, 0, "管理后端执行失败"); return;
    }
    ok = json_bool(output, "ok", 0);
    if (!json_string(output, "message", message, sizeof(message)))
        safe_copy(message, sizeof(message), ok ?
                  (action == ACTION_WIFI_APPLY ? "Wi-Fi 设置已应用" :
                   (action == ACTION_FAN_CURVE_APPLY ? "自定义曲线已应用" : "操作完成")) :
                  "操作失败");
    publish_message(action, ok, message);
}

static void *status_worker(void *unused)
{
    unsigned long long old_rx = 0, old_tx = 0;
    struct timespec old_time = {0, 0};
    struct mihomo_status cached;
    struct network_status network_cached;
    char *network_state = NULL;
    int old_valid = 0, cached_valid = 0, consecutive_failures = 0;
    int network_cached_valid = 0, network_failures = 0;
    long long next_fast_poll = 0, next_full_poll = 0, next_network_poll = 0;
    long long next_wifi_poll = 0;
    memset(&cached, 0, sizeof(cached));
    memset(&network_cached, 0, sizeof(network_cached));
    (void)unused;
    for (;;) {
        int action = ACTION_NONE, action_band = -1;
        int action_value = 0, action_value2 = 0, refresh = 0;
        int action_curve_count = 0;
        struct fan_curve_point_status action_curve[TOUCHUI_FAN_CURVE_MAX];
        long long now;
        pthread_mutex_lock(&shared_lock);
        if (!shared_action_running && shared_action != ACTION_NONE) {
            action = shared_action; shared_action = ACTION_NONE;
            action_band = shared_action_band;
            action_value = shared_action_value;
            action_value2 = shared_action_value2;
            action_curve_count = shared_action_curve_count;
            memcpy(action_curve, shared_action_curve, sizeof(action_curve));
            shared_action_curve_count = 0;
            shared_action_running = 1;
            shared_running_action = action;
            shared_generation++;
        }
        if (force_refresh) { refresh = 1; force_refresh = 0; }
        if (force_network_refresh) { next_network_poll = 0; force_network_refresh = 0; }
        pthread_mutex_unlock(&shared_lock);
        if (action != ACTION_NONE) {
            execute_action(action, action_band, action_value, action_value2,
                           action_curve, action_curve_count);
            pthread_mutex_lock(&shared_lock);
            shared_action_running = 0;
            shared_running_action = ACTION_NONE;
            shared_generation++;
            pthread_mutex_unlock(&shared_lock);
            next_full_poll = 0;
            next_network_poll = 0;
            next_wifi_poll = 0;
        }
        now = monotonic_millis();
        if (refresh) next_full_poll = 0;
        if (now >= next_full_poll) {
            struct mihomo_status fresh;
            if (collect_manager_status(&fresh)) {
                cached = fresh;
                cached_valid = 1;
                consecutive_failures = 0;
            } else if (cached_valid) {
                consecutive_failures++;
                if (consecutive_failures >= STATUS_STALE_FAILURES) cached.stale = 1;
            } else {
                consecutive_failures++;
            }
            next_full_poll = monotonic_millis() + FULL_STATUS_INTERVAL_MS;
            now = monotonic_millis();
        }
        if (now >= next_fast_poll) {
            if (cached_valid)
                update_fast_status(&cached, &old_rx, &old_tx, &old_time, &old_valid);
            pthread_mutex_lock(&shared_lock);
            if (cached_valid) shared_status = cached;
            else memset(&shared_status, 0, sizeof(shared_status));
            shared_generation++;
            pthread_mutex_unlock(&shared_lock);
            next_fast_poll = monotonic_millis() + FAST_STATUS_INTERVAL_MS;
        }
        if (now >= next_network_poll) {
            struct network_status fresh;
            if (!network_state) network_state = malloc(NETWORK_HTTP_MAX);
            if (network_state &&
                collect_network_status(&fresh, network_state, NETWORK_HTTP_MAX)) {
                network_cached = fresh;
                network_cached_valid = 1;
                network_failures = 0;
            } else if (network_cached_valid) {
                network_failures++;
                if (network_failures >= STATUS_STALE_FAILURES)
                    network_cached.stale = 1;
                update_network_clock(&network_cached);
            } else {
                network_failures++;
            }
            pthread_mutex_lock(&shared_lock);
            if (network_cached_valid) shared_network_status = network_cached;
            else memset(&shared_network_status, 0, sizeof(shared_network_status));
            shared_network_generation++;
            pthread_mutex_unlock(&shared_lock);
            next_network_poll = monotonic_millis() + NETWORK_STATUS_INTERVAL_MS;
        }
        if (now >= next_wifi_poll) {
            struct wifi_power_status fresh;
            if (collect_wifi_power_status(&fresh)) {
                pthread_mutex_lock(&shared_lock);
                shared_wifi_power_status = fresh;
                shared_wifi_generation++;
                pthread_mutex_unlock(&shared_lock);
            }
            next_wifi_poll = monotonic_millis() + WIFI_STATUS_INTERVAL_MS;
        }
        usleep(50000);
    }
    return NULL;
}
