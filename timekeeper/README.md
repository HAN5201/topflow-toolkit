# Timekeeper

在原厂网络校时完成后，通过设备已有的 Qualcomm time_genoff 基准 12 保存可信时间
偏移。下次开机时，原厂 time_daemon 可以在联网前恢复合理的系统时间，避免 RTC
停在 1970 年时 TLS 服务和 Mihomo 无法启动。

它不修改物理 RTC、不替换原厂 NTP。procd watcher 每 30 秒检查原厂同步状态，
只有 `zwrt_sntp get_sync_state` 明确完成后才保存偏移。持续离线不会超时退出；
观察到后续未同步到已同步的转换时再次刷新，服务重启保留本轮成功标记，避免重复写入。

## 离线时区

B20 存在原厂保存 UTC+8、系统却使用 UTC 的情况。组件将原厂保存的固定偏移转换为
POSIX TZ（UTC+8 为 `CST-8`），同步到系统 UCI 和 `/tmp/TZ`。实机还确认 B20 的
libc 不使用 `/etc/TZ` 文本，因此生成固定偏移 TZif v2 文件
`/data/timekeeper/localtime`，让 `/etc/localtime` 持久指向它，供进程从启动时读取。
这不调整系统 Unix 时间，也不需要联网。

支持 -12 至 +14 小时、整分钟的固定偏移。原厂启用夏令时或网络自动时区时，释放
组件管理的固定时区，交给原厂处理。遇到未提交的系统 UCI 编辑时暂缓应用，避免
提交其他设置。设置变化每 30 秒检查一次，但已缓存时区的原厂进程需要重启才能
更新显示；首次安装或变更时区后建议重启设备。

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

`running: true` 是正常常驻状态；`last_saved_epoch=none_this_boot` 表示本轮开机尚未
成功保存。`local_time`、`configured_timezone`、`effective_timezone` 和
`libc_timezone_file` 用于核对显示与实际文件。首次启动即报告已同步时仍等待至少
60 秒；离线等待期间只记录状态变化，日志超过 64 KiB 后轮转一份。procd 为异常退出
提供有界重启，不会主动重启原厂 SNTP 或改变网络连接。

## 卸载

    ./timekeeper/uninstall.sh --check
    ./timekeeper/uninstall.sh

卸载只在组件所有权标记存在时删除 `/data/time/ats_12`。如果首次安装前该偏移已经
存在，安装器不会取得其所有权，卸载时也不会删除。当前系统时间不会被回拨；下次启动
恢复原厂联网校时流程。

安装前的 timezone/zonename 单独备份，卸载时仅在系统仍使用本组件最后写入的配置时
恢复，保留用户后续自行修改的配置；组件拥有的 `/etc/localtime` 链接恢复到原厂
`/tmp/localtime`。重启可清除原厂长驻进程的时区缓存。

## 验证

    python3 timekeeper/test_timekeeper.py
    make check

2026-09-13 在 B20 上离线重启后，系统与原厂 `get_systime` 均返回 UTC+8，原厂
RTC 服务和 watcher 正常，未同步期间可信偏移的校验值保持不变。隔离测试覆盖晚于
10 分钟才联网、再次同步、服务重启、时区正负偏移及非整小时偏移、TZif 解析至
2099 年、幂等应用与回退、用户设置保护和夏令时切换。此次修复后真实联网成功的
偏移刷新尚未实测，不能把模拟测试视为联网验证。

实机验证边界和统一恢复顺序见 [RECOVERY.md](../docs/RECOVERY.md)。
