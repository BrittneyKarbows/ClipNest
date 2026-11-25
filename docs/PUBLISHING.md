# GitHub 发布指南

建议仓库名：`ClipNest`。以下为本地发布材料的使用说明。已有仓库可直接更新源码，再创建新版本 Release。

## 仓库首页

仓库描述可用：

> 剪藏 ClipNest：原生 macOS 剪贴板管理工具，支持文字、图片、链接与文件位置历史，搜索收藏、来源应用色条、深色模式和自动清理。本地存储，无需账号。

建议 Topics：`macos`、`swift`、`swiftui`、`clipboard`、`clipboard-manager`、`appkit`、`sqlite`。

## 上传源码

1. 使用 GitHub 创建 `ClipNest` 仓库。若准备推送现成目录，可先创建空仓库，避免重复生成 README。
2. 解压 `ClipNest-1.4.0-source.zip`，进入其中的 `ClipNest` 文件夹。
3. 将此文件夹中的内容作为仓库根目录：README、Sources、Resources、Tests、Xcode 工程、脚本及 docs。
4. 使用 GitHub Desktop、Git 或网页上传。不要把外层 `ClipNest` 文件夹再次套在仓库根目录，也不要把安装包当作源码提交。

使用 Git 时，可以在解压后的源码根目录运行：

```sh
git init
git add .
git commit -m "Release ClipNest 1.4.0"
git branch -M main
```

随后从你实际创建的 GitHub 仓库复制远程地址，配置 remote 并推送。请确认仓库公开范围及源码许可证符合你的选择。

`.gitignore` 已忽略编译缓存、dist、应用包、DMG、zip、用户 Xcode 状态和本地数据库。发布目录只含源码、项目资源和文档，不包含私人剪贴板历史或测试数据库。

## 创建 Release

在仓库 **Releases → Draft a new release** 中：

| 项目 | 内容 |
| --- | --- |
| Tag | `v1.4.0` |
| Title | `剪藏 ClipNest 1.4.0` |
| Description | 粘贴 `docs/RELEASE-v1.4.0.md` 的内容 |
| Attachments | 安装包、源码包、`SHA256SUMS.txt` |

将 `ClipNest-1.4.0-arm64.dmg`、`ClipNest-1.4.0-source.zip` 和 `SHA256SUMS.txt` 附加到 Release。GitHub 也会生成仓库快照的 Source code 下载，附加源码包可方便用户直接取得本次整理的完整材料。

本次交付的校验文件只列出DMG 安装包与源码 ZIP；最外层 `ClipNest-1.4.0-GitHub-Publish.zip` 是给维护者的一站式材料包，不必重复附加到 Release。

发布前可在这三个文件所在目录核验：

```sh
shasum -a 256 -c SHA256SUMS.txt
```

不要上传含私人历史的截图。首页目前使用应用图标；如需追加界面展示，可使用开发文档中的隔离演示模式制作截图。

## 许可证

材料已附 MIT 许可证，版权人为 BrittneyKarbows。请将根目录的 `LICENSE` 与源码一起上传，保留 README 中的许可证说明。MIT 允许使用、修改、分发及商业使用，并要求保留版权与许可声明；它不要求修改后的软件必须公开源码。

完整条款见仓库根目录 [LICENSE](../LICENSE)，许可证介绍见 [Choose a License](https://choosealicense.com/licenses/mit/)。
