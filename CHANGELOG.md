# 修改日志

## 1.0.2+3 (2026-05-17)

### 修复

- **多 HTML 子框架导致主体内容丢失**
  - Chrome/Edge 保存的 .mht 文件含多个 `Content-Type: text/html` 部分（主页面 + 空白子框架）
  - 解析器被后者覆盖 `htmlContent`，导致最终输出为空白 body
  - 改为 `htmlContent ??= parsed.body`，仅保留第一个 HTML 部分
  - 涉及文件：`lib/mht_parser.dart`

- **GBK 编码文件名浏览崩溃**
  - Android 文件系统中 GBK 编码的文件名在 content:// URI 中 percent-encode 为非 UTF-8 字节
  - `Uri.decodeComponent()` 按 UTF-8 解码失败，抛出 `FormatException: Unexpected extension byte`
  - 改为由 Kotlin 平台通道直接返回 `DocumentFile.name`（Android 系统已解码）
  - 新增 `MhtFileInfo` 类（含 `uri` 和 `displayName`），替换原有 `String` 路径列表
  - 涉及文件：`lib/main.dart`、`lib/file_handler.dart`、`MainActivity.kt`

- **大文件 loadHtmlString 白屏**
  - 超大 MHT 文件（30MB+）解析后 HTML 体积膨胀，超过 Android WebView `loadHtmlString` 隐式大小限制
  - 结果写入应用缓存目录，通过 `loadFile()` 加载，绕过大小限制
  - 同时启用 `NavigationDelegate.onPageFinished` 回调，待页面渲染完成后才隐藏加载动画
  - 涉及文件：`lib/mht_viewer.dart`

### 新增

- **GBK/GB2312 编码文件内容支持**
  - 解析前检测 MHT Content-Type 头中的 `charset` 声明
  - 若为 `gbk`/`gb2312`/`gb18030`，通过 Kotlin 平台通道调用 `String(bytes, charset("GBK"))` 转为 UTF-8
  - 转码后的文件重新解析，中文内容正常显示
  - 涉及文件：`lib/mht_parser.dart`、`lib/file_handler.dart`、`MainActivity.kt`

- **大文件后台 isolate 解析**
  - 大于 2MB 的文件自动在后台 isolate 中执行 `parseToHtml()`，避免阻塞 UI 线程
  - 加载提示动态显示文件大小（如「正在后台解析大文件 (30.0 MB)...」）
  - 涉及文件：`lib/mht_parser.dart`、`lib/mht_viewer.dart`

- **文件列表显示名优化**
  - 文件列表改用 Android 系统解码的 `displayName`，彻底消除编码猜测
  - 不再对文件名手动调用 `Uri.decodeComponent()`
  - 涉及文件：`lib/main.dart`

- **APK 历史版本归档**：构建产物按版本号保存在 `apk/` 目录，命名格式 `mht-viewer-v<version>-<variant>.apk`
  - 涉及文件：`apk/mht-viewer-v1.0.2+3-debug.apk`、`README.md`

## 1.0.1+2 (2026-05-17)

### 修复

- **Android 14 Scoped Storage 文件列表失败**
  - `getDirectoryPath()` 在部分设备上返回文件系统路径而非 content:// URI
  - 新增 `_pathToTreeUri()` 方法，将文件系统路径转换为 SAF document-tree URI
  - `listMhtFilesInDirectory()` 在 `dart:io` 失败后自动回退到平台通道方案
  - 涉及文件：`lib/file_handler.dart`

- **quoted-printable 中文乱码**
  - QP 解码后未将 Latin-1 字节序列重新解释为 UTF-8 字符串
  - `_decodeQuotedPrintable()` 增加 `latin1.encode()` → `utf8.decode()` 转码步骤
  - 涉及文件：`lib/mht_parser.dart`

- **quoted-printable 编码的 CSS/资源排版异常**
  - `toDataUri()` 对非 base64 资源直接使用原始 QP 字节生成 data: URI
  - 浏览器无法解析仍处于 QP 编码状态的 CSS 内容
  - 新增 QP 分支：使用解码后的 `body` 重新编码为 UTF-8 base64
  - 涉及文件：`lib/mht_parser.dart`

- **浏览文件列表中文件名显示为 URL 编码**
  - 平台通道返回的 content URI 中文件名是 percent-encoded 的
  - 对文件名和文件路径增加 `Uri.decodeComponent()` 解码
  - 涉及文件：`lib/main.dart`

- **长文件名无法查看完整名称**
  - 文件列表的 `Text` 组件使用 `TextOverflow.ellipsis` 截断
  - 改为 `SingleChildScrollView` + 横向滚动，支持滑动查看
  - 涉及文件：`lib/main.dart`

- **快速测试按钮路径硬编码**
  - 原路径 `/sdcard/test.mht` 在 Scoped Storage 下不可访问
  - 改为使用 `path_provider` 获取应用私有文档目录
  - 涉及文件：`lib/main.dart`

- **MIME boundary 跨行匹配失败（历史修复，纳入记录）**
  - Content-Type 头部分行时 `.*?` 无法跨越换行符
  - 正则增加 `dotAll: true` 标记
  - 涉及文件：`lib/mht_parser.dart`

### 新增

- **MANAGE_EXTERNAL_STORAGE 权限管理**
  - Kotlin 端新增 `isManageStorageGranted` 和 `requestManageStorage` 通道方法
  - Dart 端新增 `isManageStorageGranted()` 和 `requestManageStorage()` 函数
  - 首页新增权限提示卡片，引导用户授权「管理所有文件」
  - 涉及文件：`lib/file_handler.dart`、`lib/main.dart`、`MainActivity.kt`

- **单元测试套件**
  - MHT 解析器单元测试（边界提取、HTML 解析、中文内容、base href 注入等）
  - 使用 `buildMht()` 辅助方法创建测试数据，无需外部文件
  - 涉及文件：`test/mht_parser_test.dart`

- **GitHub 分享**
  - 仓库地址：https://github.com/IoVQI/mht-viewer
