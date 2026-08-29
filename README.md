# MU5252 Toolkit

面向 ZTE TOPFLOW MU5252 的实验性扩展工具集，当前只验证过：

- 硬件：`MU5252_HW1.0`
- 固件：`BD_ENCNMU5252V1.0.0B20`
- 架构：AArch64 / musl

仓库包含三个相互配合、也可单独阅读的组件：

| 组件 | 作用 |
|---|---|
| [`mihomo-netns`](mihomo-netns/) | 在独立 network namespace 中运行 Mihomo，并提供 IPv4 透明网关、DHCP 网关/DNS 下发与故障恢复 |
| [`mihomo-manager`](mihomo-manager/) | 把 Mihomo 状态、模式、配置、更新和网络开关接入设备原生 WebUI |
| [`touchscreen-control-center`](touchscreen-control-center/) | 通过 `LD_PRELOAD` 扩展原厂 LVGL 触屏，展示三基带、Mihomo、设备状态、散热和 Wi-Fi 控制 |

## 重要警告

这些脚本会以 root 权限修改网络命名空间、DHCP、init 服务、`rc.local` 和只读 WebUI 的 bind mount。它们不是通用 OpenWrt 软件包，也没有在其他固件版本上验证。

在执行安装前，请至少具备：

1. 可用的 root ADB；
2. 当前设备配置备份；
3. 通过串口、ADB 或配置恢复进行回退的能力；
4. 对脚本中固定地址、接口名和固件哈希的逐项确认。

触屏组件会在安装前核对原厂 `zte_topsw_devui` 的 SHA-256；不匹配时必须停止，而不是绕过检查。

## 仓库边界

本仓库只发布原创源码和公开配置模板，不包含：

- 订阅地址、代理节点、控制器密钥或真实 `config.yaml`；
- 设备抓取、日志、Cookie、序列号或配置备份；
- ZTE 固件、二进制、共享库、字体、图片或完整 WebUI 文件；
- Mihomo、Zashboard、GeoIP/GeoSite 或第三方规则缓存。

安装者需自行从各上游获取相关组件，并遵守其许可证。WebUI 安装器在本地设备上补丁当前文件，不在仓库中分发原厂文件。触屏中的上传/下载箭头由本项目运行时生成，其余图标只引用设备现有路径或已加载的固件对象。

## 开始使用

- [部署 Mihomo 透明网关](mihomo-netns/README.md)
- [安装设备 Web 管理页](mihomo-manager/README.md)
- [编译和安装触屏控制中心](touchscreen-control-center/README.md)
- [安全与敏感信息报告](SECURITY.md)

建议按以上顺序部署。触屏控制中心的数据页面依赖本机运行的 `zwrt-datad`，Mihomo 页面则依赖 `mihomo-manager`。

## 本地检查

```sh
make check
```

该命令检查 Shell/Node 语法，并用宿主编译器对触屏注入库执行严格编译。面向设备的正式产物仍应使用 AArch64 musl 交叉编译器构建。

## 状态

这是针对一台测试设备开发和实机验证的工程，不是 ZTE、Mihomo 或任何运营商的官方项目。固件升级、A/B 槽切换或 WebUI 资源变化后，必须重新审计兼容性。

## License

原创代码采用 [MIT License](LICENSE)。第三方项目和设备固件仍受各自许可证约束。
