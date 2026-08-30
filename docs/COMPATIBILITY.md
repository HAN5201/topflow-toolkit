# Compatibility boundary

本项目只在商品名 ZTE TopFlow、硬件 `MU5252_HW1.0`、固件
`BD_ENCNMU5252V1.0.0B20` 上验证。MU5252 是内部硬件标识，不是项目名，也不代表其他
同名外观或其他地区固件自动兼容。

## 固件相关接口

| 范围 | 当前依赖 |
| --- | --- |
| WebUI | `/usr/zte_web/web` 目录、U60Pro 菜单格式、`requireLogin` 路由和 RPC/ACL |
| 网络 | `br-lan`、`zte_wan`/`zte_mwan*`、`mwan3`、`mmx_mask`、`iptables`、`ebtables`、`ip netns` |
| 普通模式 | `/sbin/sdx75_set_mwan3.sh` 的已知 B20 SHA-256 与原厂调用路径 |
| 聚合模式 | `SMULTIWAN`、厂商 ICG 透明代理、`tun0` 和模式切换服务 |
| 时间 | `/usr/lib/libtime_genoff.so.1`、基准 12、原厂 RTC/SNTP UBus 对象 |
| 触屏 | 非 PIE `zte_topsw_devui`、LVGL ABI、进程内函数/素材地址和启动顺序 |
| 持久化 | `/data`、procd/OpenWrt init，以及 `/etc/rc.local` fallback |

`zwrt-datad` 要求上游 v0.9.21 或更新版本；更高版本仍需通过健康检查和界面实测，不能
仅凭版本号推断所有 schema/控制能力不变。

## 新固件验证门槛

不要只因为型号相同就把新固件 SHA 加入 allowlist。至少要验证：

1. 安装前检查会拒绝不匹配的厂商文件；
2. 安装、正常运行、停止和重复启动；
3. 锁屏、熄屏、页面切换与每秒状态刷新；
4. DHCP 接管和撤销后的客户端恢复；
5. 普通/聚合模式切换以及 Mihomo 串联；
6. 故障启动、服务崩溃、回退和完整卸载；
7. 重启持久化与 FOTA 后的恢复边界。

FOTA 可能替换 `rc.local`，但保留 `/data`。升级后从新固件重新取得基线，不要把旧
固件整份 `rc.local` 覆盖回来。恢复策略见 [RECOVERY.md](RECOVERY.md)。
