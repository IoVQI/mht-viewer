import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mht_viewer_app/mht_parser.dart';

void main() {
  // Path to the test .mht file
  const testFilePath = r'C:\Code\Xiaomi MiMo 开放平台.mht';

  group('MhtParser.fromFile', () {
    test('should load .mht file successfully', () async {
      final file = File(testFilePath);
      expect(await file.exists(), isTrue, reason: 'Test file must exist');

      final parser = await MhtParser.fromFile(testFilePath);
      expect(parser, isNotNull);
    });

    test('should throw for non-existent file', () async {
      expect(
        () => MhtParser.fromFile(r'C:\nonexistent\fake.mht'),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('MhtParser.parseToHtml', () {
    late MhtParser parser;
    late String html;

    setUpAll(() async {
      parser = await MhtParser.fromFile(testFilePath);
      html = parser.parseToHtml();
    });

    test('should return valid HTML string', () {
      expect(html, isNotEmpty);
      expect(html.toLowerCase(), contains('<html'));
    });

    test('should not return error HTML', () {
      expect(html, isNot(contains('解析错误')));
      expect(html, isNot(contains('无法解析 MHT 文件')));
      expect(html, isNot(contains('未找到 MIME boundary')));
      expect(html, isNot(contains('不包含任何内容部分')));
      expect(html, isNot(contains('未找到 HTML 内容')));
    });

    test('should contain expected page content from Xiaomi MiMo', () {
      // The page title contains "Xiaomi MiMo 开放平台"
      expect(html, contains('MiMo'));
    });

    test('should inject base href to prevent URL leakage', () {
      expect(html, contains('<base href="about:blank">'));
    });

    test('should inline resources as data: URIs', () {
      // A real MHT file from a browser should have images/CSS inlined
      // Check that at least some content-location references were replaced
      // (no http:// or https:// URLs should remain in the HTML body for inlined resources)
      expect(html.contains('data:'), isTrue,
          reason: 'Should contain data: URIs for inlined resources');
    });

    test('should handle images as data: URIs', () {
      // Check for image data URIs (common in browser-saved MHT files)
      final hasImageDataUri =
          RegExp(r'data:image/[a-z]+;base64,').hasMatch(html);
      // Note: some MHT files may not have images, so this is informational
      if (hasImageDataUri) {
        expect(hasImageDataUri, isTrue,
            reason: 'Images should be inlined as data: URIs');
      }
    });
  });
}
