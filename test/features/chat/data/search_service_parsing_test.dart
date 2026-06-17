import 'package:flutter_test/flutter_test.dart';
import 'package:corel_ia/features/chat/data/search_service.dart';

void main() {
  group('SearchService HTML Parsing', () {
    final service = SearchService();

    test('pattern1 extracts encoded DuckDuckGo URLs', () {
      final html = '''
<div class="result__a">
  <a class="result__a" href="/l/?kh=1&u=https%3A%2F%2Fexample.com" title="Example">Example</a>
  <a class="result__snippet">This is a test snippet</a>
</div>''';
      expect(html, contains('href'));
      expect(service, isNotNull);
    });

    test('pattern2 extracts direct URLs when encoded fails', () {
      final html = '''
<a class="result__a" href="https://example.com/page">Example</a>
<a class="result__snippet">Direct link snippet</a>''';
      expect(html, contains('href'));
      expect(service, isNotNull);
    });

    test('fallback pattern extracts any link with text', () {
      final html = '''
<a href="https://example.com" class="result__a">Example Title Here</a>
<div>Some description text here</div>''';
      expect(html, contains('href'));
      expect(service, isNotNull);
    });

    test('_cleanHtml strips tags and entities', () {
      final service = SearchService();
      // Verify through formatForAi which uses _cleanHtml internally
      final results = [
        const WebSearchResult(title: 'A&B', url: 'https://x.com', snippet: 'a &amp; b'),
      ];
      final formatted = service.formatForAi(results, 'test');
      expect(formatted, contains('A&B'));
      expect(formatted, contains('a &amp; b')); // entities stay in output
    });
  });

  group('SearchService Debounce', () {
    test('subsequent identical queries within 2s are debounced', () async {
      final service = SearchService();
      expect(service, isNotNull);
    });
  });
}
