# Timekeeper

在原厂网络校时完成后，通过设备已有的 Qualcomm time_genoff 基准 12 保存可信时间
偏移。下次开机时，原厂 time_daemon 可以在联网前恢复合理的系统时间，避免 RTC
停在 1970 年时 TLS 服务和 Mihomo 无法启动。

它不修改物理 RTC、不替换原厂 NTP，也不会常驻轮询。一次性 procd watcher 等
zwrt_sntp get_sync_state 明确完成后保存偏移，然后退出。

## 兼容性

当前只验证过：

- MU5252_HW1.0；
- BD_ENCNMU5252V1.0.0B20；
- /usr/lib/libtime_genoff.so.1 和应用基准 12；
- /etc/init.d/zte_ubus_bsp_rtc.init。

安装器会检查这些运行依赖。固件升级后必须重新验证，不能假设其他 ZTE/Qualcomm
设备使用相同基准或服务路径。

## 构建

需要 Docker：

    ./timekeeper/build.sh

脚本固定构建 Linux/arm64 musl 产物并写入 timekeeper/build/time-genoff。仓库不分发
预编译 helper。

## 安装与检查

    ./timekeeper/install.sh
    adb shell '/data/timekeeper/timekeeper.sh status'
    adb shell 'cat /tmp/timekeeper.log'

只有系统时间位于 2026-01-01 至 2100-01-01、且原厂明确报告 SNTP 已完成时，组件才会
写入偏移。写入期间会暂时停止占用 /dev/rtc0 的原厂 RTC 服务，并在所有退出路径恢复。

## 卸载

    ./timekeeper/uninstall.sh --check
    ./timekeeper/uninstall.sh

卸载只在组件所有权标记存在时删除 `/data/time/ats_12`。如果首次安装前该偏移已经
存在，安装器不会取得其所有权，卸载时也不会删除。当前系统时间不会被回拨；下次启动
恢复原厂联网校时流程。

实机验证边界和统一恢复顺序见 [RECOVERY.md](../docs/RECOVERY.md)。
