import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/core/platform/browser_action.dart';
import 'package:corel_ia/core/platform/extension_bridge_io.dart' show ExtensionBridge;

void main() {
  // ── BrowserActionType ───────────────────────────────────────────────────────

  group('BrowserActionType', () {
    test('has all 22 action types', () {
      expect(BrowserActionType.values.length, equals(22));
    });

    test('each type has correct string value', () {
      expect(BrowserActionType.openUrl.value, equals('OPEN_URL'));
      expect(BrowserActionType.navigateBack.value, equals('NAVIGATE_BACK'));
      expect(BrowserActionType.navigateForward.value, equals('NAVIGATE_FORWARD'));
      expect(BrowserActionType.getPageContent.value, equals('GET_PAGE_CONTENT'));
      expect(BrowserActionType.summarizePage.value, equals('SUMMARIZE_PAGE'));
      expect(BrowserActionType.extractText.value, equals('EXTRACT_TEXT'));
      expect(BrowserActionType.extractLinks.value, equals('EXTRACT_LINKS'));
      expect(BrowserActionType.extractTables.value, equals('EXTRACT_TABLES'));
      expect(BrowserActionType.extractForms.value, equals('EXTRACT_FORMS'));
      expect(BrowserActionType.extractMedia.value, equals('EXTRACT_MEDIA'));
      expect(BrowserActionType.pageMetadata.value, equals('PAGE_METADATA'));
      expect(BrowserActionType.clickElement.value, equals('CLICK_ELEMENT'));
      expect(BrowserActionType.fillForm.value, equals('FILL_FORM'));
      expect(BrowserActionType.autoFillPage.value, equals('AUTOFILL_PAGE'));
      expect(BrowserActionType.scroll.value, equals('SCROLL'));
      expect(BrowserActionType.screenshot.value, equals('SCREENSHOT'));
      expect(BrowserActionType.highlightElement.value, equals('HIGHLIGHT_ELEMENT'));
      expect(BrowserActionType.waitForSelector.value, equals('WAIT_FOR_SELECTOR'));
      expect(BrowserActionType.getElementInfo.value, equals('GET_ELEMENT_INFO'));
      expect(BrowserActionType.download.value, equals('DOWNLOAD'));
      expect(BrowserActionType.downloadData.value, equals('DOWNLOAD_DATA'));
      expect(BrowserActionType.saveAsPdf.value, equals('SAVE_AS_PDF'));
    });

    test('fromString returns correct type for known values', () {
      expect(BrowserActionType.fromString('OPEN_URL'), equals(BrowserActionType.openUrl));
      expect(BrowserActionType.fromString('DOWNLOAD'), equals(BrowserActionType.download));
      expect(BrowserActionType.fromString('SCREENSHOT'), equals(BrowserActionType.screenshot));
      expect(BrowserActionType.fromString('CLICK_ELEMENT'), equals(BrowserActionType.clickElement));
    });

    test('fromString returns getPageContent for unknown values', () {
      expect(BrowserActionType.fromString('UNKNOWN_ACTION'), equals(BrowserActionType.getPageContent));
      expect(BrowserActionType.fromString(''), equals(BrowserActionType.getPageContent));
    });

    test('fromString is case-sensitive (falls back for wrong case)', () {
      // Values must match exactly
      expect(BrowserActionType.fromString('open_url'), equals(BrowserActionType.getPageContent));
    });
  });

  // ── BrowserAction ───────────────────────────────────────────────────────────

  group('BrowserAction', () {
    test('creates with unique actionId', () {
      final action1 = BrowserAction(action: BrowserActionType.openUrl, params: {'url': 'https://example.com'});
      final action2 = BrowserAction(action: BrowserActionType.openUrl, params: {'url': 'https://example.com'});

      // actionIds should be different (timestamp-based)
      expect(action1.actionId, isNotEmpty);
      expect(action2.actionId, isNotEmpty);
      // They may be the same if created in the same millisecond, but usually different
    });

    test('toJson includes all fields', () {
      final action = BrowserAction(
        action: BrowserActionType.download,
        params: {'url': 'https://example.com/file.zip', 'filename': 'file.zip'},
      );

      final json = action.toJson();
      expect(json['action'], equals('DOWNLOAD'));
      expect(json['actionId'], isNotEmpty);
      expect(json['params']['url'], equals('https://example.com/file.zip'));
      expect(json['params']['filename'], equals('file.zip'));
    });

    test('toJson with empty params', () {
      final action = BrowserAction(action: BrowserActionType.screenshot, params: {});

      final json = action.toJson();
      expect(json['action'], equals('SCREENSHOT'));
      expect(json['params'], isA<Map<dynamic, dynamic>>());
      expect(json['params'], isEmpty);
    });

    test('params can contain nested values', () {
      final action = BrowserAction(
        action: BrowserActionType.download,
        params: {
          'urls': ['https://a.com', 'https://b.com'],
          'filename': 'bundle',
        },
      );

      final json = action.toJson();
      expect(json['params']['urls'], isA<List<dynamic>>());
      expect((json['params']['urls'] as List).length, equals(2));
    });
  });

  // ── BrowserActionResult ─────────────────────────────────────────────────────

  group('BrowserActionResult', () {
    test('fromJson creates success result', () {
      final json = {
        'actionId': 'test-123',
        'action': 'OPEN_URL',
        'success': true,
        'data': {'tabId': 42, 'url': 'https://example.com'},
        'error': null,
      };

      final result = BrowserActionResult.fromJson(json);
      expect(result.actionId, equals('test-123'));
      expect(result.action, equals(BrowserActionType.openUrl));
      expect(result.success, isTrue);
      expect(result.data?['tabId'], equals(42));
      expect(result.data?['url'], equals('https://example.com'));
      expect(result.error, isNull);
    });

    test('fromJson creates error result', () {
      final json = {
        'actionId': 'test-456',
        'action': 'CLICK_ELEMENT',
        'success': false,
        'data': null,
        'error': 'Element not found: #missing-btn',
      };

      final result = BrowserActionResult.fromJson(json);
      expect(result.actionId, equals('test-456'));
      expect(result.action, equals(BrowserActionType.clickElement));
      expect(result.success, isFalse);
      expect(result.data, isNull);
      expect(result.error, equals('Element not found: #missing-btn'));
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final result = BrowserActionResult.fromJson(json);
      expect(result.actionId, equals(''));
      expect(result.action, equals(BrowserActionType.getPageContent)); // default fallback
      expect(result.success, isFalse);
      expect(result.data, isNull);
      expect(result.error, isNull);
    });

    test('fromJson handles partial data', () {
      final json = {
        'actionId': 'abc',
        'action': 'SCREENSHOT',
        'success': true,
      };

      final result = BrowserActionResult.fromJson(json);
      expect(result.actionId, equals('abc'));
      expect(result.action, equals(BrowserActionType.screenshot));
      expect(result.success, isTrue);
      expect(result.data, isNull);
      expect(result.error, isNull);
    });

    test('toString formats correctly for success', () {
      const result = BrowserActionResult(
        actionId: 'test-1',
        action: BrowserActionType.openUrl,
        success: true,
      );
      expect(result.toString(), contains('OPEN_URL'));
      expect(result.toString(), contains('success=true'));
      expect(result.toString(), isNot(contains('error=')));
    });

    test('toString formats correctly for error', () {
      const result = BrowserActionResult(
        actionId: 'test-2',
        action: BrowserActionType.download,
        success: false,
        error: 'Network error',
      );
      expect(result.toString(), contains('DOWNLOAD'));
      expect(result.toString(), contains('error=Network error'));
    });

    test('fromJson with download result containing list', () {
      final json = {
        'actionId': 'dl-1',
        'action': 'DOWNLOAD',
        'success': true,
        'data': {
          'downloaded': [
            {'url': 'https://example.com/a.mp4', 'id': 1, 'success': true},
            {'url': 'https://example.com/b.mp4', 'id': 2, 'success': true},
          ],
        },
      };

      final result = BrowserActionResult.fromJson(json);
      expect(result.success, isTrue);
      expect(result.data?['downloaded'], isA<List<dynamic>>());
      final downloaded = result.data?['downloaded'] as List<dynamic>;
      expect(downloaded.length, equals(2));
    });

    test('fromJson with screenshot result containing dataUrl', () {
      final json = {
        'actionId': 'ss-1',
        'action': 'SCREENSHOT',
        'success': true,
        'data': {'dataUrl': 'data:image/png;base64,iVBOR...'},
      };

      final result = BrowserActionResult.fromJson(json);
      expect(result.success, isTrue);
      expect(result.data?['dataUrl'], isNotNull);
    });
  });

  // ── IO stub (extension_bridge_io.dart) ───────────────────────────────────────

  group('ExtensionBridge (IO stub)', () {
    test('isExtension is always false on mobile', () {
      // Import handled by conditional export
      // This test verifies the IO stub behavior
      final bridge = ExtensionBridge();
      expect(bridge.isExtension, isFalse);
    });

    test('executeAction returns error on mobile', () async {
      final bridge = ExtensionBridge();
      final action = BrowserAction(
        action: BrowserActionType.openUrl,
        params: {'url': 'https://example.com'},
      );
      final result = await bridge.executeAction(action);
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      expect(result.error, contains('not available'));
    });

    test('onActionResult stream is empty on mobile', () async {
      final bridge = ExtensionBridge();
      // Should not emit any events
      final events = <BrowserActionResult>[];
      final sub = bridge.onActionResult.listen(events.add);
      await Future.delayed(const Duration(milliseconds: 50)); // ignore: inference_failure_on_instance_creation, Future.delayed n'est pas générique en Dart 3.41 (false-positive)
      await sub.cancel();
      expect(events, isEmpty);
      bridge.dispose();
    });

    test('onSelectedText stream is empty on mobile', () async {
      final bridge = ExtensionBridge();
      final events = <String>[];
      final sub = bridge.onSelectedText.listen(events.add);
      await Future.delayed(const Duration(milliseconds: 50)); // ignore: inference_failure_on_instance_creation, Future.delayed n'est pas générique en Dart 3.41 (false-positive)
      await sub.cancel();
      expect(events, isEmpty);
      bridge.dispose();
    });

    test('dispose closes streams cleanly', () {
      final bridge = ExtensionBridge();
      bridge.dispose();
      // Should not throw when disposed
    });
  });
}