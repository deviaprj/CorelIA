/// Résultat de recherche web retourné par le backend.
class SearchResult {
  final String query;
  final List<SearchItem> results;
  final String? source;
  final bool isCached;

  const SearchResult({
    required this.query,
    required this.results,
    this.source,
    this.isCached = false,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        query: json['query'] as String,
        results: (json['results'] as List)
            .map((e) => SearchItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        source: json['source'] as String?,
        isCached: json['isCached'] as bool? ?? false,
      );
}

class SearchItem {
  final String title;
  final String link;
  final String? snippet;
  final String? displayedLink;

  const SearchItem({
    required this.title,
    required this.link,
    this.snippet,
    this.displayedLink,
  });

  factory SearchItem.fromJson(Map<String, dynamic> json) => SearchItem(
        title: json['title'] as String,
        link: json['link'] as String,
        snippet: json['snippet'] as String?,
        displayedLink: json['displayedLink'] as String?,
      );
}
