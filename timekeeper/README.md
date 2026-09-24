# Timekeeper

在原厂网络校时完成后，通过设备已有的 Qualcomm time_genoff 基准 12 保存可信时间
偏移。下次开机时，原厂 time_daemon 可以在联网前恢复合理的系统时间，避免 RTC
停在 1970 年时 TLS 服务和 Mihomo 无法启动。

它不修改物理 RTC。对已审核的 B20 原厂 NTP 客户端应用 UTC 兼容补丁，保留原厂
服务器选择、数据包校验、重试及同步通知。procd watcher 每 30 秒检查原厂同步状态，
只有 `zwrt_sntp get_sync_state` 明确完成后才保存偏移。持续离线不会超时退出；
观察到后续未同步到已同步的转换时再次刷新，服务重启保留本轮成功标记，避免重复写入。

## UTC 校时与本地显示

B20 原厂 ntpclient 会在 NTP UTC 秒数上叠加时区和夏令时，再写系统时钟。仅安装
UTC+8 TZif 会让联网后的本地显示重复加 8 小时，并把错误 Unix 时间保存到 base 12。

安装器通过 ADB 私下读取设备自己的 ntpclient，先核对完整 SHA-256，再生成兼容副本。
补丁只将 `0x4d44` 改为跳转到 `0x4e88`，绕过时区/DST 算术；NTP 秒与小数转换、
包校验、clock_settime 和后续通知不变。原厂二进制不进入仓库或发布包。未知固件拒绝安装。

通过 bind mount 加载副本，原厂只读分区不变。组件注册 `S10timekeeper`，并在
原厂 `/etc/init.d/zte_topsw_ntp` 的 `start_service` 开头加入可撤销的前置步骤；
实机没有标准 `rcS` 脚本，不能只依赖 S10/S49 的编号保证先后。首次启用会丢弃旧同步标志，通过原厂启动脚本重新启动 NTP 客户端；只有
新的成功结果才能保存偏移。已有客户端仍映射未修复程序时禁止保存。

组件将原厂保存的固定偏移转换为
POSIX TZ（UTC+8 为 `CST-8`），同步到系统 UCI 和 `/tmp/TZ`。实机还确认 B20 的
libc 不使用 `/etc/TZ` 文本，因此生成固定偏移 TZif v2 文件
`/data/timekeeper/localtime`，让 `/etc/localtime` 持久指向它，供进程从启动时读取。
时区显示本身不调整 Unix 时间；真实 NTP 同步负责把系统时钟恢复为 UTC。升级后
如果持续离线，已有的错误系统时钟和偏移不会被盲目减 8 小时，必须等待新鲜同步。

支持 -12 至 +14 小时、整分钟的固定偏移。原厂启用夏令时或网络自动时区时，释放
组件管理的固定时区和 NTP 挂载，交给原厂处理，且停止保存可信偏移；这些模式尚未
实现标准 UTC 兼容，安装器要求关闭它们。遇到未提交的系统 UCI 编辑时暂缓应用，避免
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

需要 Docker、Python 3 和 root ADB：

    ./timekeeper/build.sh

脚本固定构建 Linux/arm64 musl 产物并写入 timekeeper/build/time-genoff。仓库不分发
预编译 helper。

## 安装与检查

    ./timekeeper/install.sh
    adb shell '/data/timekeeper/timekeeper.sh status'
    adb shell 'cat /tmp/timekeeper.log'

只有 UTC 兼容路径有效、当前为 SNTP 模式、系统时间位于 2026-01-01 至
2100-01-01、且原厂明确报告 SNTP 已完成时，组件才会
写入偏移。写入期间会暂时停止占用 /dev/rtc0 的原厂 RTC 服务，并在所有退出路径恢复。

`running: true` 是正常常驻状态；`last_saved_epoch=none_this_boot` 表示本轮开机尚未
成功保存。`local_time`、`configured_timezone`、`effective_timezone` 和
`libc_timezone_file` 用于核对显示与实际文件。首次启动即报告已同步时仍等待至少
60 秒；离线等待期间只记录状态变化，日志超过 64 KiB 后轮转一份。procd 为异常退出
提供有界重启。兼容挂载切换会重启原厂 NTP 客户端以生效，不改变网络连接。

## 卸载

    ./timekeeper/uninstall.sh --check
    ./timekeeper/uninstall.sh

卸载只在组件所有权标记存在时删除 `/data/time/ats_12`。如果首次安装前该偏移已经
存在，安装器不会取得其所有权，卸载时也不会删除。卸载撤销 NTP 挂载并重新启动原厂校时客户端；后续原厂校时恢复固件原有的时间语义。

安装前的 timezone/zonename 单独备份，卸载时仅在系统仍使用本组件最后写入的配置时
恢复，保留用户后续自行修改的配置；组件拥有的 `/etc/localtime` 链接恢复到原厂
`/tmp/localtime`。重启可清除原厂长驻进程的时区缓存。

## 验证

    python3 timekeeper/test_timekeeper.py
    make check

2026-09-13 在 B20 上离线重启后，系统与原厂 `get_systime` 均返回 UTC+8，原厂
RTC 服务和 watcher 正常，未同步期间可信偏移的校验值保持不变。隔离测试覆盖晚于
10 分钟才联网、再次同步、服务重启、时区正负偏移及非整小时偏移、TZif 解析至
2099 年、幂等应用与回退、用户设置保护和夏令时切换。上次验证未覆盖真实联网成功，未发现原厂会再次叠加时区的问题。

2026-09-24 UTC 兼容修复已执行提取二进制的 AArch64 指令仿真，覆盖 UTC、+8、
-5、+5.5、+12.75，写时钟参数均保持 UTC。实机先阻断 NTP 验证旧偏移不被保存，
恢复后原厂服务器真实同步成功：Unix 时间与主机相差不足 1 秒，`date` 和原厂
`get_systime` 均显示 UTC+8，base 12 更新为正确时间。

暂停 NTP 自启后实机重启，未同步阶段未复现 8 小时偏移，base 12 校验值保持不变。
该次离线恢复比电脑快约 19 秒；这是尚未解决的秒级恢复误差，不能宣称离线精确校时。
恢复 NTP 后再次真实同步、自动保存成功，Unix 秒与主机相差约 1 秒。重复安装及
watcher 重启未重复写入已保存的偏移。加上原厂 NTP 启动前置步骤后，第二次正常
自动重启中，原厂客户端直接加载 UTC 副本，约 50 秒时已经同步成功。手动设置时间的 mktime 路径只做静态检查，
未在实机切换手动模式；DST/网络自动时区不在 UTC 兼容支持范围。

实机验证边界和统一恢复顺序见 [RECOVERY.md](../docs/RECOVERY.md)。
