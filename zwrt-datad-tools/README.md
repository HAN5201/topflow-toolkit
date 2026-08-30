# zwrt-datad maintenance

触屏控制中心依赖 [33333s/zwrt-datad](https://github.com/33333s/zwrt-datad)
提供的 /state、/events 和受约束 /control 接口。MU5252 扩展能力已经合并进
上游 v0.9.21；本项目要求 v0.9.21 或更新版本。

update-zwrt-datad.sh 是宿主机上的手动更新器，不会自动定时更新，也不会修改固件
分区、启动槽或 bootloader。

## 能力

    ./zwrt-datad-tools/update-zwrt-datad.sh check
    ./zwrt-datad-tools/update-zwrt-datad.sh update
    ./zwrt-datad-tools/update-zwrt-datad.sh rollback
    ./zwrt-datad-tools/update-zwrt-datad.sh permissions

更新器会：

1. 读取上游最新 Release；
2. 只接受精确的 zwrt-datad-aarch64 资产；
3. 校验 GitHub 提供的 SHA-256 digest；
4. 在设备端 staging 后再次核对摘要和可执行性；
5. 原子替换并轮询 /healthz；
6. 失败时自动恢复 zwrt-datad.prev。

多台 ADB 设备同时在线时设置 ADB_SERIAL。可通过 ZWRT_DATAD_REPO、
ZWRT_DATAD_ASSET 和 ZWRT_DATAD_DIR 显式覆盖上游、资产名和设备目录。

## 权限策略

持久目录、二进制和 service.sh 应为 root:root 0755；auth.token、日志和散热配置
应为 0600；rollback/staging 应仅 root 可访问。permissions 子命令只修复这些
固定路径的权限，不更新二进制。
