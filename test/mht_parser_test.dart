import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mht_viewer_app/mht_parser.dart';

/// Builds a minimal valid MHT byte sequence with the given HTML body.
List<int> buildMht(String htmlBody) {
  const boundary = '----TestBoundary';
  return utf8.encode(
    'From: <test>\r\n'
    'Subject: test\r\n'
    'Date: Sun, 17 May 2026 00:00:00 -0000\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: multipart/related;\r\n'
    '\ttype="text/html";\r\n'
    '\tboundary="$boundary"\r\n'
    '\r\n'
    '------TestBoundary\r\n'
    'Content-Type: text/html\r\n'
    'Content-Transfer-Encoding: 8bit\r\n'
    '\r\n'
    '$htmlBody\r\n'
    '------TestBoundary--\r\n',
  );
}

/// Writes a temporary .mht file and parses it with MhtParser.fromFile.
Future<MhtParser> writeAndParse(List<int> bytes) async {
  final tmpDir = Directory.systemTemp;
  final file = File('${tmpDir.path}/test_${DateTime.now().microsecondsSinceEpoch}.mht');
  await file.writeAsBytes(bytes);
  try {
    return await MhtParser.fromFile(file.path);
  } finally {
    await file.delete();
  }
}

void main() {
  group('MhtParser.fromFile', () {
    test('should load and parse a valid MHT file', () async {
      final bytes = buildMht('<p>Hello World</p>');
      final parser = await writeAndParse(bytes);
      expect(parser, isNotNull);
    });

    test('should throw for non-existent file', () async {
      expect(
        () async => MhtParser.fromFile(r'C:\nonexistent\fake_file_xyz123.mht'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MhtParser.parseToHtml', () {
    test('should parse minimal MHT with simple HTML', () async {
      final parser = await writeAndParse(buildMht('<p>Hello World</p>'));
      final html = parser.parseToHtml();

      expect(html, isNotEmpty);
      expect(html, contains('<p>Hello World</p>'));
    });

    test('should parse MHT with Chinese content', () async {
      final parser = await writeAndParse(buildMht('<h1>你好世界</h1>'));
      final html = parser.parseToHtml();

      expect(html, isNotEmpty);
      expect(html, contains('你好世界'));
    });

    test('should not return error HTML for valid MHT', () async {
      final parser = await writeAndParse(buildMht('<p>test</p>'));
      final html = parser.parseToHtml();

      expect(html, isNot(contains('解析错误')));
      expect(html, isNot(contains('无法解析 MHT 文件')));
    });

    test('should return error HTML when no boundary found', () {
      final parser = MhtParser.fromBytes(
        utf8.encode('Content-Type: text/html'),
      );
      final html = parser.parseToHtml();

      expect(html, contains('解析错误'));
      expect(html, contains('未找到 MIME boundary'));
    });

    test('should inject base href to prevent URL leakage', () async {
      final parser = await writeAndParse(
        buildMht('<html><head></head><body>test</body></html>'),
      );
      final html = parser.parseToHtml();

      expect(html, contains('<base href="about:blank">'));
    });
  });
}
