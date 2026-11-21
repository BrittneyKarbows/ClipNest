# 开发与构建

## 技术组成

SwiftUI 负责卡片与设置界面；AppKit 负责菜单栏、窗口、剪贴板和应用图标；SQLite 保存历史与分类；Carbon 注册全局快捷键；ApplicationServices 提供直接粘贴所需能力；ServiceManagement 管理登录启动。无第三方运行依赖，不需要下载 npm、CocoaPods 或 Swift Package。

## 目录

```text
ClipNest/
├── README.md
├── CHANGELOG.md
├── COPYRIGHT.md
├── LICENSE
├── ClipNest.xcodeproj/
├── Sources/
│   ├── main.swift               # 应用入口
│   ├── AppController.swift      # 生命周期、窗口和交互协调
│   ├── Models.swift             # 数据模型、偏好、登录项
│   ├── ClipStore.swift          # SQLite 与定时清理
│   ├── ClipboardService.swift   # 捕获、图片文件预览、复制恢复
│   ├── PasteService.swift       # 目标应用切换与粘贴状态机
│   ├── HotKey.swift             # 快捷键校验与注册
│   ├── IconPalette.swift        # 本地图标与代表色
│   ├── PanelView.swift          # 历史卡片面板
│   └── SettingsView.swift       # 六类设置与快捷键录制
├── Resources/
│   ├── Info.plist
│   ├── AppIcon.icns
│   ├── AppIcon.png
│   └── GenerateIcon.swift
├── Tests/
│   ├── main.swift
│   └── PasteChecks.swift
├── docs/
├── build.sh
├── test.sh
└── test-paste.sh
```

## 构建

环境要求：Mac、可用的 Xcode Command Line Tools 或 Xcode。脚本通过 `xcrun swiftc` 编译，默认目标为 `arm64-apple-macosx13.0`。

```sh
./build.sh ./dist/ClipNest.app
```

中间文件默认保存在 `.build/`。需要独立构建目录时：

```sh
CLIPNEST_BUILD_DIR=./.build-release ./build.sh ./dist/ClipNest.app
```

也可打开 `ClipNest.xcodeproj`，选择 ClipNest scheme。发布前应在自己的环境确认构建、签名和实际运行；目前 Xcode 工程已完成结构校验，交付包由命令行脚本构建。

## 签名与分发

默认使用 ad hoc 签名。已有签名身份时，可将钥匙串中实际存在的身份名称传入：

```sh
CLIPNEST_SIGN_IDENTITY='你的实际签名身份名称' ./build.sh ./dist/ClipNest.app
```

此参数只选择签名身份，不会自动完成 Developer ID 分发所需的全部配置、公证或 stapling。面向其他 Mac 分发前，应自行配置正式签名、公证，并在另一台 Mac 验证安装。

本地 ad hoc 构建更新后，系统可能要求重新授予辅助功能权限。应用仅显示当前进程的权限状态，不会自动修改系统授权。辅助功能已经允许但按键权限未生效时，完整退出并重启同一构建后再检查。

## 测试

```sh
./test.sh
./test-paste.sh
```

1.2.0 的检查结果：102 项核心检查、26 项直接粘贴状态检查通过。

核心检查覆盖 SQLite 持久化、内容去重、Unicode、收藏与分类、数量裁剪、暂停与应用排除、隐私标记、文字/链接/图片/多文件捕获和恢复、图片文件预览与缓存、快捷键冲突及偏好保存、登录项模拟状态、面板防误触、主题偏好迁移、过期边界、月末与闰年、最后复制时间、清理服务启停及收藏分类保护。

直接粘贴检查使用模拟环境覆盖目标切换、等待焦点、修饰键释放、菜单与权限变化、超时取消，以及微信图片按键路径，验证不提前发送、不重复发送和不误粘贴到其他目标。

核心测试使用临时数据库、独立命名剪贴板及临时快捷键，测试结束后释放。粘贴测试不操控真实应用，不修改权限。若受限环境无法访问 macOS 剪贴板服务，请在本机普通终端运行测试。

实机回归应覆盖外观切换、六页设置、快捷键录制、登录启动、菜单栏隐藏恢复，以及目标应用中的文字与图片粘贴。自动清理回归应使用隔离数据库，避免用私人历史作测试数据。

## 演示模式

仅开发调试时，可启动可执行文件并传入 `--demo`：

```sh
./dist/ClipNest.app/Contents/MacOS/ClipNest --demo
```

演示模式使用临时数据库，不监听系统剪贴板，不向正式历史写入示例内容。请先退出正在运行的正常副本，避免同时启动多个实例造成快捷键冲突。

## 发布

更新 `Resources/Info.plist` 的版本与构建号，运行两组检查，再构建和校验签名。发布流程见 [GitHub 发布指南](PUBLISHING.md)。
