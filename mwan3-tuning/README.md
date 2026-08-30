# mwan3 tuning

修复普通 MULTIWAN 模式下三个相互关联的问题：

1. 原厂全流量规则排在 HTTPS sticky 前面，导致 sticky 实际不命中；
2. 蜂窝链路只做单次极小 Ping，不生成可用延迟/丢包质量；
3. 任一 WAN 事件会清空整个 conntrack 表。

组件为 Mihomo 虚拟网关单独保留非 sticky HTTPS 分流，普通 LAN HTTPS 保持 600 秒
sticky；三路蜂窝采用短采样、多轮防抖；线路失败时只删除对应 fwmark 的 IPv4
conntrack，恢复事件不清理健康连接。

## 不分发厂商脚本

仓库不包含 sdx75_set_mwan3.sh。安装器从目标设备读取当前原厂脚本，要求其 SHA-256
与已验证 B20 文件完全一致，并保存到 /data。运行时 bind mount 的是一个很小的原创
wrapper：先执行设备自己的原厂副本，再应用本项目规则。

摘要不匹配时安装必须停止，不能跳过。

## 配置

默认配置见 config.example：

    TRACK_IPS='199.7.83.42 180.76.76.76 192.58.128.30'
    MIHOMO_SOURCE='192.168.11.11'

这些探测目标和阈值来自一次真实三 WAN 验证，不保证适合其他地区。安装前应从三条
活动线路分别测试。设备端配置位于 /data/local/mwan3-tuning/config。

## 安装

    ./mwan3-tuning/install.sh

如果设备已存在其他 /sbin/sdx75_set_mwan3.sh bind mount，安装器会拒绝覆盖。当前为
MULTIWAN 时，安装会重启 mwan3 并短暂影响新连接；不会切换普通/聚合模式。

选择性清理映射可以只读检查：

    adb shell 'INTERFACE=zte_mwan4 /etc/hotplug.d/iface/90-mwan3-selective-conntrack --inspect'

## 卸载

    ./mwan3-tuning/uninstall.sh --check
    ./mwan3-tuning/uninstall.sh

卸载会移除 wrapper bind mount 和 hotplug 链接，恢复安装前的探测目标；若当前处于
MULTIWAN，则使用安装时保存的原厂脚本重新生成配置并重启 mwan3。它不会切换模式，
也不会改 Mihomo、DHCP 或 IPv6。

公开安装器的“设备本地复制 + wrapper”打包方式尚未在另一台干净设备上完成端到端
安装—重启—卸载验证；底层规则、质量退出和单 WAN 故障清理已在 B20 实机验证。
