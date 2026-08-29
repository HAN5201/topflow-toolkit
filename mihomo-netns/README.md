# Mihomo transparent gateway

该组件让 Mihomo 在独立 network namespace 中运行。宿主系统保留原厂路由和蜂窝调度，仅把 DHCP 客户端的 IPv4 网关/DNS 指向 namespace 中的固定地址。

```text
LAN client
  -> DHCP gateway/DNS 192.168.11.11
  -> veth mh-host / mh-uplink
  -> namespace mihomo
  -> mihomo0 TUN
  -> 192.168.11.1
  -> vendor MultiWAN/ICG
```

固定参数：

| 项目 | 值 |
|---|---|
| namespace | `mihomo` |
| 虚拟网关 | `192.168.11.11/24` |
| 上游网关 | `192.168.11.1` |
| 显式代理示例 | `192.168.11.11:7890` |
| 控制器示例 | `192.168.11.11:9090` |
| bridge mark | `0x5252` |

请先确认 `.11` 不在 DHCP 池内，也没有被静态地址、租约、接口或邻居占用。

## 准备私有文件

仓库不会保存核心、配置、规则或 GeoIP 数据。先复制模板并填写自己的 provider 和 controller secret：

```sh
cp examples/config.example.yaml /path/to/private-config.yaml
```

从 [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo/releases) 获取 Linux arm64 核心，并自行核对上游摘要。

## 安装

```sh
MIHOMO_BINARY=/path/to/mihomo-linux-arm64 \
MIHOMO_CONFIG=/path/to/private-config.yaml \
./install.sh
```

可选参数：

- `MIHOMO_RULES_DIR`：需要一并复制的私有规则目录；
- `MIHOMO_COUNTRY_MMDB`：私有 `Country.mmdb` 路径；
- `ADB_BIN`：自定义 ADB 命令路径。

安装器先在 `/data/mihomo/.install` 检查候选核心和配置，通过后才停止旧服务并替换正式文件。现有核心和配置会保存为 `.prev`。

## 管理

```sh
adb shell '/etc/init.d/mihomo-netns status'
adb shell '/etc/init.d/mihomo-netns restart'
adb shell '/etc/init.d/mihomo-netns disable; /etc/init.d/mihomo-netns stop'
```

长期停止必须通过 init 服务。直接执行 `mihomo-netns.sh stop` 时，procd 监控可能再次启动它。

## DHCP 与失败模式

启用 DHCP 网关后，Option 3 和 6 都指向 `.11`。服务停止会撤销当前下发，但保留期望状态；重新启用后恢复。

这是 fail-closed 设计：已经取得 `.11` 租约的客户端在 Mihomo 启动失败时会暂时断网。部署前必须准备一台不依赖该 DHCP 路径的管理终端。

当前方案只接管 IPv4。若 LAN IPv6 保持开启，客户端可能绕过 Mihomo。

## 完全卸载

先卸载 Web 管理页，再运行：

```sh
./uninstall.sh --check
./uninstall.sh
```

卸载器会停止服务、撤销 namespace、host 规则和 DHCP Option 3/6，然后删除本组件的设备端文件。私有配置会保留，除非显式设置 `REMOVE_PRIVATE_DATA=1`。
