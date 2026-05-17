import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'file_handler.dart';
import 'folder_store.dart';
import 'mht_viewer.dart';

void main() => runApp(const MhtViewerApp());

class MhtViewerApp extends StatelessWidget {
  const MhtViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MHT Viewer',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _storagePermitted = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    FolderStore.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _checkPermissions() async {
    final granted = await isManageStorageGranted();
    if (mounted) setState(() => _storagePermitted = granted);
  }

  // -----------------------------------------------------------------------
  // Folder management
  // -----------------------------------------------------------------------

  Future<void> _pickAndAddFolder() async {
    final dirPath = await pickDirectory();
    if (dirPath == null || !mounted) return;

    final alias = await _showAliasDialog(
      title: '为新文件夹命名',
      initial: _defaultAlias(dirPath),
    );
    if (alias == null || alias.trim().isEmpty) return;

    await FolderStore.add(alias.trim(), dirPath);
    FolderStore.select(dirPath);
    if (mounted) setState(() {});
  }

  Future<void> _pickFolder() async {
    final dirPath = await pickDirectory();
    if (dirPath == null || !mounted) return;

    // Ask whether to save
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存此文件夹？'),
        content: Text(dirPath),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('仅本次使用'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (save == true && mounted) {
      final alias = await _showAliasDialog(
        title: '为文件夹命名',
        initial: _defaultAlias(dirPath),
      );
      if (alias != null && alias.trim().isNotEmpty) {
        await FolderStore.add(alias.trim(), dirPath);
      }
    }

    FolderStore.select(dirPath);
    if (mounted) setState(() {});
  }

  Future<void> _editAlias(int index) async {
    final folder = FolderStore.folders[index];
    final newAlias = await _showAliasDialog(
      title: '重命名',
      initial: folder.alias,
    );
    if (newAlias != null && newAlias.trim().isNotEmpty && mounted) {
      await FolderStore.rename(index, newAlias.trim());
      setState(() {});
    }
  }

  Future<void> _deleteFolder(int index) async {
    final folder = FolderStore.folders[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('确定要删除 "${folder.alias}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FolderStore.remove(index);
      if (mounted) setState(() {});
    }
  }

  // -----------------------------------------------------------------------
  // Browse files
  // -----------------------------------------------------------------------

  Future<void> _browseFiles() async {
    final dir = FolderStore.selectedPath;
    if (dir == null) return;

    // Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final files = await listMhtFilesInDirectory(dir);

    if (mounted) Navigator.of(context).pop(); // dismiss loading

    if (!mounted) return;

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该文件夹中没有 .mht 或 .mhtml 文件')),
      );
      return;
    }

    // Show file list dialog
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _FileListDialog(files: files),
    );

    if (selected != null && mounted) {
      final readablePath = await ensureReadablePath(selected);
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MhtViewerPage(filePath: readablePath)),
      );
    }
  }

  // -----------------------------------------------------------------------
  // Random
  // -----------------------------------------------------------------------

  Future<void> _openTestFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final testPath = '${dir.path}/test.mht';
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MhtViewerPage(filePath: testPath)),
    );
  }

  Future<void> _startRandom() async {
    final dir = FolderStore.selectedPath;
    if (dir == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final path = await pickRandomFromDirectory(dir);

    if (mounted) Navigator.of(context).pop();

    if (path != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MhtViewerPage(filePath: path)),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该文件夹中没有 .mht 或 .mhtml 文件')),
      );
    }
  }

  // -----------------------------------------------------------------------
  // Permissions
  // -----------------------------------------------------------------------

  Widget _buildStoragePermissionCard() {
    return Card(
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '未授予"管理所有文件"权限',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Android 14+ 需要此权限才能直接读取存储中的 .mht 文件。\n'
              '不使用此权限也可通过"选择文件夹"浏览文件。',
              style: TextStyle(fontSize: 13, color: Colors.orange.shade800),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                ),
                onPressed: () async {
                  await requestManageStorage();
                  await Future.delayed(const Duration(seconds: 2));
                  await _checkPermissions();
                },
                child: const Text('前往授权'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Dialogs
  // -----------------------------------------------------------------------

  Future<String?> _showAliasDialog({
    required String title,
    required String initial,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '输入别名',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _defaultAlias(String path) {
    final segments = path.split('/');
    return segments.where((s) => s.isNotEmpty).lastOrNull ?? '文件夹';
  }

  // -----------------------------------------------------------------------
  // UI
  // -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final folders = FolderStore.folders;
    final selectedPath = FolderStore.selectedPath;
    final selectedFolder = selectedPath != null
        ? folders.cast<SavedFolder?>().firstWhere(
              (f) => f!.path == selectedPath,
              orElse: () => null,
            )
        : null;
    final hasSelection = selectedPath != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MHT Viewer'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          // -- 存储权限提示 --
          if (!_storagePermitted) _buildStoragePermissionCard(),
          // -- 已保存的文件夹 --
          _buildSavedFoldersSection(folders),
          const SizedBox(height: 24),

          // -- 当前选择 --
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.folder, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '当前选择',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedFolder?.alias ?? '未选择文件夹',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            color: hasSelection ? null : Colors.grey.shade500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _pickFolder,
                        child: const Text('选择文件夹'),
                      ),
                    ],
                  ),
                  if (selectedFolder != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      selectedFolder.path,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _browseFiles,
                            icon: const Icon(Icons.list, size: 18),
                            label: const Text('浏览文件'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _startRandom,
                            icon: const Icon(Icons.casino, size: 18),
                            label: const Text('开始随机'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openTestFile,
              icon: const Icon(Icons.bug_report, size: 18),
              label: const Text('快速测试 (test.mht)'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSavedFoldersSection(List<SavedFolder> folders) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_special, size: 20),
                const SizedBox(width: 8),
                Text(
                  '已保存的文件夹',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (folders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '还没有保存的文件夹',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                ),
              ),
            for (int i = 0; i < folders.length; i++)
              _buildFolderRow(folders[i], i),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickAndAddFolder,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('添加文件夹'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderRow(SavedFolder folder, int index) {
    final isSelected = folder.path == FolderStore.selectedPath;

    return InkWell(
      onTap: () {
        FolderStore.select(folder.path);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: isSelected
            ? BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: Row(
          children: [
            Radio<String>(
              value: folder.path,
              groupValue: FolderStore.selectedPath,
              visualDensity: VisualDensity.compact,
              onChanged: (_) {
                FolderStore.select(folder.path);
                setState(() {});
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.alias,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    folder.path,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: () => _editAlias(index),
              tooltip: '重命名',
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 18,
                  color: Colors.red.shade400),
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteFolder(index),
              tooltip: '删除',
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// File list dialog for "浏览文件"
// =============================================================================

class _FileListDialog extends StatelessWidget {
  final List<String> files;

  const _FileListDialog({required this.files});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('选择文件 (${files.length})'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: files.length,
          itemBuilder: (_, i) {
            final fileName = Uri.decodeComponent(files[i].split('/').last);
            final sub = files[i].length > 60
                ? '...${Uri.decodeComponent(files[i].substring(files[i].length - 50))}'
                : Uri.decodeComponent(files[i]);

            return ListTile(
              leading: const Icon(Icons.description),
              title: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(fileName),
              ),
              subtitle: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text(
                  sub,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
              onTap: () => Navigator.pop(context, files[i]),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
