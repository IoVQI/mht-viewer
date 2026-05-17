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
    } catch (_) {}
  }

  // Path 2: content:// URI — delegate to Android platform channel
  if (_isContentUri(dirPath)) {
    try {
      final uris = await _channel.invokeMethod('listMhtFiles', {
        'uri': dirPath,
      });
      if (uris is List) {
        return uris.map((u) => u.toString()).toList();
      }
    } catch (_) {}
  }

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
