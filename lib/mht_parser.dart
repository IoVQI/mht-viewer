import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'file_handler.dart';

/// Top-level helper for [Isolate.run] — must be a top-level function.
String _runParse(_ParsePayload payload) {
  return MhtParser._(payload.bytes, payload.text).parseToHtml();
}

/// Simple payload carrying the data needed for isolate parsing.
class _ParsePayload {
  final List<int> bytes;
  final String text;
  const _ParsePayload(this.bytes, this.text);
}

/// Parses an MHT (MIME HTML / .mhtml) file and extracts HTML with inlined resources.
class MhtParser {
  final List<int> _bytes;
  late final String _text;

  MhtParser._(this._bytes, this._text);

  /// Byte size of the loaded file.
  int get byteLength => _bytes.length;

  /// Creates an [MhtParser] from raw bytes (useful for testing).
  MhtParser.fromBytes(List<int> bytes)
      : _bytes = bytes,
        _text = _decodeBytes(bytes);

  static String _decodeBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  /// Creates an [MhtParser] from a file path.
  ///
  /// Auto-detects encoding from MHT headers. If the file uses GBK/GB2312
  /// encoding, it is converted to UTF-8 via the platform channel first.
  static Future<MhtParser> fromFile(String filePath) async {
    var bytes = await File(filePath).readAsBytes();
    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      // Detect charset from MIME headers (ASCII-safe)
      final charset = _detectCharset(bytes);
      if (charset != null) {
        final converted = await convertToUtf8(filePath, charset);
        if (converted != null) {
          bytes = await File(converted).readAsBytes();
        }
      }
      try {
        text = utf8.decode(bytes);
      } catch (_) {
        text = latin1.decode(bytes);
      }
    }
    return MhtParser._(bytes, text);
  }

  /// Extracts the charset from MHT Content-Type headers.
  /// The header section is ASCII, so Latin-1 decode is safe.
  static String? _detectCharset(List<int> bytes) {
    final head = latin1.decode(bytes.length > 4096 ? bytes.sublist(0, 4096) : bytes);
    final match = RegExp(
      r'Content-Type:.*?charset\s*=\s*"?([^";\s\n\r]+)',
      caseSensitive: false,
    ).firstMatch(head);
    if (match == null) return null;
    final charset = match.group(1)!.toLowerCase();
    const gbkNames = ['gbk', 'gb2312', 'gb18030', 'gb_2312', 'gb_2312-80'];
    return gbkNames.contains(charset) ? charset : null;
  }

  /// Parses MHT content on a background isolate to keep the UI responsive.
  /// Use for files >2 MB.
  static Future<String> parseInIsolate(List<int> bytes, String text) {
    return Isolate.run(() => _runParse(_ParsePayload(bytes, text)));
  }

  /// Parses to HTML. Automatically uses a background isolate for files >2 MB
  /// to avoid janking the UI thread.
  Future<String> parseToHtmlAsync() {
    if (_bytes.length > 2 * 1024 * 1024) {
      return parseInIsolate(_bytes, _text);
    }
    return Future.value(parseToHtml());
  }

  /// Parses the MHT content and returns an HTML string with all resources
  /// inlined as data: URIs, suitable for display in a WebView.
  String parseToHtml() {
    final boundary = _extractBoundary();
    if (boundary == null) {
      return _errorHtml('无法解析 MHT 文件：未找到 MIME boundary 声明。<br>'
          '请确认文件是有效的 .mht 或 .mhtml 格式。');
    }

    final parts = _splitParts(boundary);
    if (parts.isEmpty) {
      return _errorHtml('MHT 文件中不包含任何内容部分。');
    }

    String? htmlContent;
    final Map<String, String> dataUris = {};

    for (final part in parts) {
      final parsed = _parsePart(part, _bytes, _text);
      if (parsed == null) continue;

      if (parsed.contentType.contains('text/html') ||
          parsed.contentType.contains('text/htm')) {
        // Only keep the first (main) HTML part — later text/html parts are
        // typically embedded iframes or sub-frames that lack meaningful content.
        htmlContent ??= parsed.body;
      } else {
        final dataUri = parsed.toDataUri();
        if (parsed.contentLocation.isNotEmpty) {
          dataUris[parsed.contentLocation] = dataUri;
        }
        if (parsed.contentId.isNotEmpty) {
          // cid: references may appear with or without angle brackets in the HTML
          dataUris['cid:${parsed.contentId}'] = dataUri;
        }
      }
    }

    if (htmlContent == null) {
      return _errorHtml('MHT 文件中未找到 HTML 内容。');
    }

    // Replace resource URLs with data: URIs. Iterate by key length descending
    // so longer (more specific) URLs are replaced first.
    final sortedEntries = dataUris.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in sortedEntries) {
      htmlContent = htmlContent!.replaceAll(entry.key, entry.value);
    }

    // Inject a base element so any remaining relative URLs don't leak.
    htmlContent = htmlContent!.replaceFirst(
      RegExp('<head[^>]*>', caseSensitive: false),
      '<head><base href="about:blank">',
    );
    if (!htmlContent.contains('<base href=')) {
      htmlContent = htmlContent.replaceFirst(
        '<html>', '<html><head><base href="about:blank"></head>',
      );
    }

    return htmlContent;
  }

  // ---------------------------------------------------------------------------
  // Boundary extraction
  // ---------------------------------------------------------------------------

  String? _extractBoundary() {
    // Match Content-Type: multipart/related; boundary="..." or boundary=...
    final match = RegExp(
      r'''Content-Type:\s*multipart/related;.*?boundary\s*=\s*"([^"]+)"''',
      caseSensitive: false,
      multiLine: true,
      dotAll: true,
    ).firstMatch(_text);
    if (match != null) return match.group(1);

    // Try without quotes: boundary=somevalue
    final match2 = RegExp(
      r'Content-Type:\s*multipart/related;.*?boundary\s*=\s*(\S+)',
      caseSensitive: false,
      multiLine: true,
      dotAll: true,
    ).firstMatch(_text);
    return match2?.group(1);
  }

  // ---------------------------------------------------------------------------
  // Part splitting
  // ---------------------------------------------------------------------------

  List<String> _splitParts(String boundary) {
    final parts = <String>[];
    final marker = '--$boundary';
    final markerLen = marker.length;

    int pos = _text.indexOf(marker);
    if (pos == -1) return parts;
    pos += markerLen;

    while (pos < _text.length) {
      // Check for end marker: --boundary-- or --boundary--\n
      if (_text.length > pos + 1 && _text.substring(pos, pos + 2) == '--') break;
      if (_text.length > pos && _text[pos] == '-') {
        // Might be a single dash (edge case)
      }

      // Skip the newline after --boundary
      if (pos < _text.length && _text[pos] == '\r') pos++;
      if (pos < _text.length && _text[pos] == '\n') pos++;

      // Find the next boundary marker
      final nextMarker = _text.indexOf(marker, pos);
      int partEnd;

      if (nextMarker == -1) {
        partEnd = _text.length;
      } else {
        // Walk back over the \r\n that precedes the next marker
        partEnd = nextMarker;
        if (partEnd > 0 && _text[partEnd - 1] == '\n') partEnd--;
        if (partEnd > 0 && _text[partEnd - 1] == '\r') partEnd--;
      }

      if (partEnd > pos) {
        parts.add(_text.substring(pos, partEnd));
      }

      if (nextMarker == -1) break;
      pos = nextMarker + markerLen;
    }

    return parts;
  }

  // ---------------------------------------------------------------------------
  // Part parsing
  // ---------------------------------------------------------------------------

  _ParsedPart? _parsePart(String part, List<int> fullBytes, String fullText) {
    final headerBodyMatch =
        RegExp(r'^(.*?)\r?\n\r?\n(.*)$', dotAll: true).firstMatch(part);
    if (headerBodyMatch == null) return null;

    final headers = _parseHeaders(headerBodyMatch.group(1)!);
    final rawBody = headerBodyMatch.group(2)!;

    // Find the byte range of rawBody in the full text to extract binary data
    final bodyStart = fullText.indexOf(rawBody);
    final bodyBytes = (bodyStart != -1)
        ? fullBytes.sublist(
            bodyStart,
            bodyStart + rawBody.length > fullBytes.length
                ? fullBytes.length
                : bodyStart + rawBody.length,
          )
        : latin1.encode(rawBody);

    return _ParsedPart(
      contentType: headers['content-type'] ?? 'text/plain',
      contentLocation: headers['content-location'] ?? '',
      contentId: headers['content-id']?.replaceAll(RegExp(r'[<>]'), '') ?? '',
      contentTransferEncoding:
          headers['content-transfer-encoding'] ?? '',
      rawBody: rawBody,
      rawBytes: bodyBytes,
    );
  }

  Map<String, String> _parseHeaders(String section) {
    final map = <String, String>{};
    String? currentKey;
    for (final line in section.split('\n')) {
      final trimmed = line.trimRight();
      // Continuation lines start with whitespace
      if ((trimmed.startsWith(' ') || trimmed.startsWith('\t')) &&
          currentKey != null) {
        map[currentKey] = map[currentKey]! + ' ' + trimmed.trim();
        continue;
      }
      final colon = trimmed.indexOf(':');
      if (colon == -1) continue;
      final key = trimmed.substring(0, colon).trim().toLowerCase();
      final value = trimmed.substring(colon + 1).trim();
      map[key] = value;
      currentKey = key;
    }
    return map;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _errorHtml(String message) {
    return '<html><head><meta charset="utf-8"></head>'
        '<body style="font-family:sans-serif;padding:24px;color:#333;">'
        '<h2 style="color:#c62828;">解析错误</h2>'
        '<p style="line-height:1.6;">$message</p>'
        '</body></html>';
  }
}

// =============================================================================
// Internal parsed-part representation
// =============================================================================

class _ParsedPart {
  final String contentType;
  final String contentLocation;
  final String contentId;
  final String contentTransferEncoding;
  final String rawBody;
  final List<int> rawBytes;

  _ParsedPart({
    required this.contentType,
    required this.contentLocation,
    required this.contentId,
    required this.contentTransferEncoding,
    required this.rawBody,
    required this.rawBytes,
  });

  /// Returns the decoded body as a String (for text content types).
  String get body {
    switch (contentTransferEncoding.toLowerCase()) {
      case 'base64':
        try {
          final normalized = rawBody.replaceAll(RegExp(r'\s+'), '');
          final decoded = base64Decode(normalized);
          try {
            return utf8.decode(decoded);
          } catch (_) {
            return latin1.decode(decoded);
          }
        } catch (_) {
          return rawBody;
        }
      case 'quoted-printable':
        return _decodeQuotedPrintable(rawBody);
      default:
        return rawBody;
    }
  }

  /// Builds a data: URI for this resource.
  String toDataUri() {
    if (contentTransferEncoding.toLowerCase() == 'base64') {
      final normalized = rawBody.replaceAll(RegExp(r'\s+'), '');
      return 'data:$contentType;base64,$normalized';
    }
    if (contentTransferEncoding.toLowerCase() == 'quoted-printable') {
      return 'data:$contentType;base64,${base64Encode(utf8.encode(body))}';
    }
    // Encode raw bytes as base64 for binary safety
    return 'data:$contentType;base64,${base64Encode(rawBytes)}';
  }

  /// Decodes quoted-printable encoding.
  static String _decodeQuotedPrintable(String input) {
    // Strip trailing whitespace from each line
    String result = input.replaceAll(RegExp(r'[ \t]+\r?\n'), '\n');
    // Soft line breaks
    result = result.replaceAll('=\r\n', '');
    result = result.replaceAll('=\n', '');
    // =XX hex decoding: each =XX becomes the corresponding byte
    result = result.replaceAllMapped(
      RegExp(r'=([0-9A-Fa-f]{2})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    );
    // The decoded string is a Latin-1 representation of a UTF-8 byte sequence.
    // Convert Latin-1 chars → raw bytes → decode as UTF-8.
    try {
      return utf8.decode(latin1.encode(result));
    } catch (_) {
      return result;
    }
  }
}
