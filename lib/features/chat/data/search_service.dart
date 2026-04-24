import 'package:dio/dio.dart';
import '../../../core/api/dio_client.dart';
import 'models/search_result.dart';

/// Exception spécifique au service de recherche.
class SearchException implements Exception {
  final String message;
  const SearchException(this.message);
  @override
  String toString() => 'SearchException: $message';
}

/// Service de recherche web via le backend FastAPI.
class SearchService {
  final Dio _dio;

  SearchService({Dio? dio}) : _dio = dio ?? DioClientFactory.create();

  /// Effectue une recherche web via le backend.
  /// Le backend utilise DuckDuckGo (gratuit) avec fallback SerpAPI (Pro).
  Future<SearchResult> search(String query, {String? lang}) async {
    try {
      final response = await _dio.get(
        '/search',
        queryParameters: {
          'q': query,
          if (lang != null) 'lang': lang,
        },
      );

      if (response.statusCode == 200 && response.data is Map) {
        return SearchResult.fromJson(response.data as Map<String, dynamic>);
      }
      throw const SearchException('Réponse inattendue du serveur de recherche');
    } on DioException catch (e) {
      final msg = e.response?.data?['detail'] as String?;
      throw SearchException(msg ?? 'Erreur réseau lors de la recherche');
    } catch (e) {
      throw SearchException(e.toString());
    }
  }
}
