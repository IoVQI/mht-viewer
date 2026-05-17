# 修改日志

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
