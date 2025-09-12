import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../l10n/app_localizations.dart';
import '../search_service.dart';

class BraveSearchService extends SearchService<BraveOptions> {
  @override
  String get name => 'Brave Search';
  
  @override
  Widget description(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Text(l10n.searchProviderBraveDescription, style: const TextStyle(fontSize: 12));
  }
  
  @override
  Future<SearchResult> search({
    required String query,
    required SearchCommonOptions commonOptions,
    required BraveOptions serviceOptions,
  }) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = 'https://api.search.brave.com/res/v1/web/search?q=$encodedQuery&count=${commonOptions.resultSize}';
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'X-Subscription-Token': serviceOptions.apiKey,
        },
      ).timeout(Duration(milliseconds: commonOptions.timeout));
      
      if (response.statusCode != 200) {
        throw Exception('API request failed: ${response.statusCode}');
      }
      
      final data = jsonDecode(response.body);
      final webResults = data['web']?['results'] as List? ?? [];
      final results = webResults.map((item) {
        return SearchResultItem(
          title: item['title'] ?? '',
          url: item['url'] ?? '',
          text: item['description'] ?? '',
        );
      }).toList();
      
      return SearchResult(items: results);
    } catch (e) {
      throw Exception('Brave search failed: $e');
    }
  }
}
