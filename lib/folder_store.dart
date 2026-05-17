import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SavedFolder {
  String alias;
  String path;
  DateTime addedAt;

  SavedFolder({
    required this.alias,
    required this.path,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'path': path,
        'addedAt': addedAt.toIso8601String(),
      };

  factory SavedFolder.fromJson(Map<String, dynamic> json) => SavedFolder(
        alias: json['alias'] as String,
        path: json['path'] as String,
        addedAt: DateTime.parse(json['addedAt'] as String),
      );
}

class FolderStore {
  static final List<SavedFolder> _folders = [];
  static String? _selectedPath;
  static bool _loaded = false;

  static List<SavedFolder> get folders => List.unmodifiable(_folders);
  static String? get selectedPath => _selectedPath;

  static Future<File> _storeFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/mht_viewer_folders.json');
  }

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _storeFile();
      if (!await file.exists()) return;
      final content = await file.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      _folders.clear();
      for (final item in list) {
        _folders.add(SavedFolder.fromJson(item as Map<String, dynamic>));
      }
    } catch (_) {}
  }

  static Future<void> _persist() async {
    try {
      final file = await _storeFile();
      await file.writeAsString(
        jsonEncode(_folders.map((f) => f.toJson()).toList()),
      );
    } catch (_) {}
  }

  static void select(String? path) {
    _selectedPath = path;
    if (path != null) {
      // Move selected folder to top
      final idx = _folders.indexWhere((f) => f.path == path);
      if (idx > 0) {
        final item = _folders.removeAt(idx);
        _folders.insert(0, item);
        _persist();
      }
    }
  }

  static Future<void> add(String alias, String path) async {
    // Remove duplicate path if exists
    _folders.removeWhere((f) => f.path == path);
    _folders.insert(0, SavedFolder(alias: alias, path: path));
    await _persist();
  }

  static Future<void> remove(int index) async {
    if (index < 0 || index >= _folders.length) return;
    if (_folders[index].path == _selectedPath) {
      _selectedPath = null;
    }
    _folders.removeAt(index);
    await _persist();
  }

  static Future<void> rename(int index, String newAlias) async {
    if (index < 0 || index >= _folders.length) return;
    _folders[index].alias = newAlias;
    await _persist();
  }
}
