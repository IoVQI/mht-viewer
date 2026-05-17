import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'mht_parser.dart';

/// Displays a parsed MHT file in a full-screen WebView.
class MhtViewerPage extends StatefulWidget {
  final String filePath;

  const MhtViewerPage({super.key, required this.filePath});

  @override
  State<MhtViewerPage> createState() => _MhtViewerPageState();
}

class _MhtViewerPageState extends State<MhtViewerPage> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;
  String _statusText = '正在解析 MHT 文件...';
  File? _tempFile;

  static const _largeThreshold = 2 * 1024 * 1024; // 2 MB

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
        ),
      );
    _loadContent();
  }

  @override
  void dispose() {
    _tempFile?.delete();
    super.dispose();
  }

  Future<void> _loadContent() async {
    try {
      final parser = await MhtParser.fromFile(widget.filePath);
      final isLarge = parser.byteLength > _largeThreshold;

      if (isLarge) {
        if (mounted) setState(() => _statusText = '正在后台解析大文件 (${(parser.byteLength / 1024 / 1024).toStringAsFixed(1)} MB)...');
      }

      final html = await parser.parseToHtmlAsync();

      if (isLarge) {
        // Use app cache dir (accessible to WebView) rather than system temp
        final cacheDir = await getTemporaryDirectory();
        _tempFile = File('${cacheDir.path}/mht_parsed.html');
        await _tempFile!.writeAsString(html);
        if (mounted) setState(() => _statusText = '正在加载页面...');
        await _controller.loadFile(_tempFile!.path);
      } else {
        await _controller.loadHtmlString(html, baseUrl: 'about:blank');
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.filePath.split('/').last;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          fileName,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_statusText),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('加载失败', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    return WebViewWidget(controller: _controller);
  }
}
