# MHT Viewer

极简 MHT 文件查看器，用于在 Android 设备上浏览 `.mht` / `.mhtml` 格式的网页存档文件。

## 功能

- 读取并解析 MHT (MIME HTML) 文件，提取 HTML 正文和内嵌资源（CSS、图片、字体等）
- 所有资源自动转为 data: URI 内联，无需网络连接即可完整渲染
- 支持 **quoted-printable** 和 **base64** 两种内容传输编码
- 文件夹管理：保存常用文件夹、浏览文件列表、随机打开
- 适配 Android 14+ Scoped Storage，通过 SAF (Storage Access Framework) 访问文件

## 技术栈

| 层 | 技术 |
|---|---|
| 框架 | Flutter 3.x (Dart) |
| 平台 | Android (Kotlin) |
| WebView | webview_flutter ^4.10 |
| 文件选择 | file_picker ^8.1 (SAF) |
| 路径 | path_provider ^2.1 |

## 构建

### 前置条件

- Flutter SDK ≥ 3.6.0
- Android SDK (API 24+)
- Android Studio 或命令行工具

### 编译

```bash
# 克隆仓库
git clone https://github.com/IoVQI/mht-viewer.git
cd mht-viewer

# 获取依赖
flutter pub get

# 构建调试版 APK (通用架构)
flutter build apk --debug

# 构建发布版 APK (按架构拆分)
flutter build apk --release
```

APK 输出路径：`build/app/outputs/flutter-apk/`

### 运行测试

```bash
flutter test
```

## 使用说明

1. 启动应用后，首页可**添加文件夹**或**选择文件夹**（单次使用不保存）
2. 选中文件夹后，点击**浏览文件**查看该目录下的所有 .mht 文件
3. 点击文件名即可打开并渲染页面
4. 点击**开始随机**会随机打开一个 .mht 文件
5. 快速测试按钮使用应用内部存储中的 test.mht 文件

### 权限说明

- 默认通过 **SAF 文件选择器**访问文件，无需额外权限
- 可前往系统设置授予「管理所有文件」权限以获得直接文件系统访问能力
- INTERNET 权限仅为 WebView 基础需求，应用不会发起网络请求

## 修改日志

详细的版本修改记录见 [CHANGELOG.md](./CHANGELOG.md)。

## 许可

MIT License
