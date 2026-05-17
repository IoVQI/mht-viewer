import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

const _channel = MethodChannel('mht_viewer_app/file');

/// Lists all .mht / .mhtml files in the given directory.
///
/// For regular filesystem paths, uses `dart:io` [Directory].
/// For `content://` URIs (Android SAF), delegates to the platform channel
/// which uses [androidx.documentfile.provider.DocumentFile] for reliable
/// document-tree traversal.
Future<List<String>> listMhtFilesInDirectory(String dirPath) async {
  // Path 1: regular filesystem directory
  if (!_isContentUri(dirPath)) {
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final files = <String>[];
        await for (final entity in dir.list(recursive: false)) {
          if (entity is File) {
            final name = entity.path.toLowerCase();
            if (name.endsWith('.mht') || name.endsWith('.mhtml')) {
              files.add(entity.path);
            }
          }
        }
        if (files.isNotEmpty) return files;
      }
      // dir exists but no MHT files found → return empty
      return [];
    } catch (_) {
      // Permission denied (scoped storage) — fall through to platform channel
    }
  }

  // Path 2: content:// URI or constructed tree URI from filesystem path
  final treeUri = _isContentUri(dirPath) ? dirPath : _pathToTreeUri(dirPath);
  try {
    final uris = await _channel.invokeMethod('listMhtFiles', {
      'uri': treeUri,
    });
    if (uris is List && uris.isNotEmpty) {
      return uris.map((u) => u.toString()).toList();
    }
  } catch (_) {}

  return [];
}

/// Picks one MHT file at random from the given directory.
///
/// Returns a readable filesystem path (content URIs are copied to the app
/// cache first), or `null` if no MHT files were found.
Future<String?> pickRandomFromDirectory(String dirPath) async {
  final files = await listMhtFilesInDirectory(dirPath);
  if (files.isEmpty) return null;

  final randomIndex = Random().nextInt(files.length);
  return ensureReadablePath(files[randomIndex]);
}

/// Opens the system directory picker and returns the path / URI string.
Future<String?> pickDirectory() async {
  return FilePicker.platform.getDirectoryPath();
}

/// Ensures the given path (which may be a `content://` URI) resolves to
/// a plain filesystem path readable by `dart:io` / WebView.
Future<String> ensureReadablePath(String pathOrUri) async {
  if (!_isContentUri(pathOrUri)) return pathOrUri;
  final cached = await _copyToCache(pathOrUri);
  return cached ?? pathOrUri;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Returns true if [MANAGE_EXTERNAL_STORAGE] is granted.
Future<bool> isManageStorageGranted() async {
  try {
    return await _channel.invokeMethod<bool>('isManageStorageGranted') ?? false;
  } catch (_) {
    return false;
  }
}

/// Opens the system settings page for granting [MANAGE_EXTERNAL_STORAGE].
Future<void> requestManageStorage() async {
  try {
    await _channel.invokeMethod('requestManageStorage');
  } catch (_) {}
}

/// Converts a filesystem path to an Android document-tree URI suitable for
/// the platform channel's `listMhtFiles` method.
String _pathToTreeUri(String path) {
  // Normalise: strip trailing slash, map /sdcard/ → /storage/emulated/0/
  var normalised = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  if (normalised == '/sdcard' || normalised.startsWith('/sdcard/')) {
    normalised = '/storage/emulated/0${normalised.substring(7)}';
  }

  // Extract the relative path after the primary storage root
  const roots = ['/storage/emulated/0/', '/storage/emulated/0', '/storage/sdcard0/'];
  String? relative;
  for (final root in roots) {
    if (normalised == root.substring(0, root.length - 1)) {
      relative = '';
      break;
    }
    if (normalised.startsWith(root)) {
      relative = normalised.substring(root.length);
      break;
    }
  }
  if (relative == null) return path; // unknown root

  // Encode as primary%3A<path> (standard Android tree URI format)
  final encoded = Uri.encodeComponent('primary:$relative').replaceAll('%2F', '/');
  return 'content://com.android.externalstorage.documents/tree/$encoded';
}

bool _isContentUri(String path) => path.startsWith('content://');

Future<String?> _copyToCache(String contentUri) async {
  try {
    return await _channel.invokeMethod<String>('readFile', {
      'uri': contentUri,
    });
  } catch (_) {
    return null;
  }
}
