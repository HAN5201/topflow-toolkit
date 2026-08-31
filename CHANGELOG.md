# Changelog

## Unreleased

- 触屏网络仪表将大陆四家运营商归一化显示为“中国移动/中国联通/中国电信/中国广电”；
- 运营商、详情摘要、地址和身份等单行字段仅在溢出时循环滚动，且不再被每秒状态刷新重置动画。

## v0.1.1 — 2026-08-30

- 不再把 `/proc/mounts` 的 source 字段当作单文件 bind mount 的原始文件路径；
- 通过挂载目标存在性与 source/target 的 device:inode 判断挂载所有权；
- start 保持幂等，stop/uninstall 会清理本组件意外叠加的全部顶层挂载，但不触碰无关挂载；
- Mihomo Manager 同步采用所有权检查，并拒绝在完整菜单仍叠加时安装或卸载；
- 增加 B20 实机临时双层 bind mount 回归脚本。

## v0.1.0 — 2026-08-30

TopFlow Toolkit 首个正式版本。

### 设备功能

- 独立 network namespace 中的 Mihomo IPv4 透明网关；
- 接入厂商 WebUI 的 Mihomo 管理页；
- 原生 LVGL 触屏控制中心与三路蜂窝网络仪表；
- Qualcomm `time_genoff` 可信时间持久化；
- 普通 MULTIWAN 的规则、链路质量和选择性 conntrack 调优；
- 从设备当前 WebUI 生成完整隐藏菜单的本地补丁器；
- `zwrt-datad` 手动检查、更新、健康验证与回滚工具。

### 工程边界

- 固件锁定到已验证的 MU5252 B20；
- 不分发厂商二进制、完整 WebUI、字体、图片或修改后的厂商脚本；
- 不保存设备抓取、凭据、订阅、真实代理配置或身份信息；
- 提供分组件卸载、统一恢复、Root ADB、网络架构与 ICG 聚合说明。

公开安装器仍应按实验性改机处理；其中完整 WebUI 菜单和 MULTIWAN wrapper 的新打包
方式已经静态/合成测试，但尚未在第二台干净设备完成安装—重启—卸载全链路验证。
