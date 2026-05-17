import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'mht_parser.dart';

/// Displays a parsed MHT file in a full-screen WebView.
///
/// Shows a [CircularProgressIndicator] during parsing, then renders the HTML
/// in a [WebViewWidget]. Includes an AppBar with the file name and a back
/// button.
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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);
    _loadContent();
  }

  Future<void> _loadContent() async {
    try {
      final parser = await MhtParser.fromFile(widget.filePath);
      final html = parser.parseToHtml();
      await _controller.loadHtmlString(html, baseUrl: 'about:blank');
      if (mounted) setState(() => _loading = false);
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
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在解析 MHT 文件...'),
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
