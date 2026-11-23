# 剪藏 ClipNest 1.2.1

本次更新统一了剪藏的图标与 GitHub 首页展示。

## 更新内容

- **全新黑白图标**：以清晰的剪贴板夹扣、纸张和叠页表达剪贴板历史，保持简洁和辨识度。
- **应用内统一**：面板标题、设置和应用图标使用同一套资源。
- **README 首页**：居中大图标，配有版本、macOS、Apple Silicon、Swift / SwiftUI、MIT 徽章，以及下载和反馈导航。
- **源码资源**：包含原始图稿、标准 ICNS 和可重新生成图标尺寸的 Swift 脚本。

原有剪贴板历史、搜索、收藏分类、直接粘贴、自定义快捷键、主题与自动清理功能继续保留。本次未修改捕获、存储或直接粘贴逻辑。

## 下载与升级

- `ClipNest-1.2.1-arm64.zip`：Apple Silicon / macOS 13+ 安装包，附 MIT 许可证。
- `ClipNest-1.2.1-source.zip`：完整源码、图标、Xcode 工程、构建脚本和文档。
- `SHA256SUMS.txt`：以上附件的 SHA-256 校验值。

请先退出旧版，再替换“应用程序”中的 `ClipNest.app`。现有历史与偏好保存在应用包外，会继续沿用。

当前包使用 ad hoc 签名，未经过 Developer ID 签名与 Apple 公证。更新后如直接粘贴显示未授权，请在系统辅助功能中移除旧条目，添加当前 `/Applications/ClipNest.app` 并开启，再完整退出并重新打开。跨设备运行可能受到 macOS 安全检查限制。

1.2.0 的 102 项核心检查和 26 项直接粘贴状态检查是此前的验证记录；1.2.1 检查图标资源、原生构建、签名与应用内显示。

本项目采用 MIT 许可证。

开发者：**BrittneyKarbows**  
邮箱：[BrittneyKarbows@gmail.com](mailto:BrittneyKarbows@gmail.com)  
GitHub：[BrittneyKarbows](https://github.com/BrittneyKarbows)
