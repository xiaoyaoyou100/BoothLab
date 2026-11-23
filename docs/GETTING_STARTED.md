# 运行与构建指南

## 归档环境

| 项目 | 已验证的值 |
| --- | --- |
| 主机与 IDE | Windows 11 x64，DevEco Studio 5.0.13.240 |
| SDK | HarmonyOS SDK 5.0.5.165（API 17），兼容与目标版本 5.0.5(17) |
| 工程 | ArkTS、ArkUI、Stage，Bundle com.example.boothlab，应用版本 1.0.0 |
| 构建目标 | 入口模块 entry、target default、product default、debug |
| 构建工具 | Hvigor / Hvigor OHOS 插件 5.17.6，Node.js 18.20.1，JBR 17.0.12 |
| 依赖 | OHPM 5.0.19。锁定开发依赖为 @ohos/hypium 1.0.21、@ohos/hamock 1.0.0。 |
| ArkTS 相关配置 | caseSensitiveCheck 与 useNormalizedOHMUrl 为 true。独立视口 runner 使用 SDK TypeScript 4.9.5-r4。 |

[应用配置](../AppScope/app.json5) · [构建配置](../build-profile.json5) · [模块配置](../entry/src/main/module.json5) · [Hvigor 配置](../hvigor/hvigor-config.json5) · [依赖锁文件](../oh-package-lock.json5)

## 从源码运行

~~~powershell
git clone https://github.com/xiaoyaoyou100/BoothLab.git
Set-Location BoothLab
git switch --detach 205faeaa60e07673e7fd04662f344f4e751a19e8
~~~

需要复现冻结验收时，使用上面的固定提交。在 DevEco Studio 打开工程根目录，配置 API 17 SDK，并同步工程依赖。选择 entry 为运行模块，选择 API 17 Phone 模拟器作为部署目标。安装并启动后，应看到展构的方案库，可新建命名方案并进入编辑器。

## Windows 命令行构建

把下面的 IDE 安装目录换成自己的路径。若工具已在 PATH，也可以直接调用对应 Windows 启动器。先同步依赖并确保缓存可用，再执行离线构建。

~~~powershell
$devecoInstall = '<DevEco Studio 安装目录>'
$ohpm = Join-Path $devecoInstall 'tools\ohpm\bin\ohpm.bat'
$hvigor = Join-Path $devecoInstall 'tools\hvigor\bin\hvigorw.bat'
& $ohpm install
& $hvigor assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug --no-daemon --offline
~~~

验收归档中的命令完成 CompileArkTS 和 PackageHap，退出码为 0，产物位于 entry/build/default/outputs/default/entry-default-unsigned.hap。归档 HAP 为 1,087,311 字节，SHA-256 为 10C503DC0B64164B164D3BDF66F66ADBA98E2AC4238BEE0A6F1B6719F4E8CCDA。该指纹仅用于识别归档制品。

## 安装与签名

当前工程的 signingConfigs 数组为空。指定 API 17 Phone 专用模拟器已验证 debug unsigned HAP 的安装、启动和核心操作。换用其他设备时，请按该设备和平台要求配置签名，再使用 DevEco Studio 部署。[测试范围](TESTING.md) · [已知限制](LIMITATIONS.md)
