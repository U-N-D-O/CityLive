import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/offline_search_entry.dart';
import 'offline_router.dart';

class OfflineDataRepository {
  const OfflineDataRepository({required this.entries, required this.router});

  final List<OfflineSearchEntry> entries;
  final OfflineRouter router;

  List<String> get placeGroups {
    final groups = entries
        .where((entry) => entry.isPlaceListing)
        .map((entry) => entry.group)
        .toSet();
    final sorted = groups.toList()
      ..sort((left, right) => _groupSort(left).compareTo(_groupSort(right)));
    return sorted;
  }

  List<String> subcategoriesForGroup(String group) {
    final subcategories =
        entries
            .where((entry) => entry.group == group && entry.isPlaceListing)
            .map((entry) => entry.subcategory)
            .toSet()
            .toList()
          ..sort();
    return subcategories;
  }

  List<OfflineSearchEntry> placesForGroup(
    String group, {
    String? subcategory,
    int limit = 80,
  }) {
    final places =
        entries.where((entry) {
          if (!entry.isPlaceListing || entry.group != group) {
            return false;
          }
          return subcategory == null || entry.subcategory == subcategory;
        }).toList()..sort((left, right) {
          final subcategoryCompare = left.subcategory.compareTo(
            right.subcategory,
          );
          if (subcategoryCompare != 0) {
            return subcategoryCompare;
          }
          return left.label.compareTo(right.label);
        });

    return places.take(limit).toList(growable: false);
  }

  static Future<OfflineDataRepository> load() async {
    final searchJson = await rootBundle.loadString(
      'assets/data/nuuk_search_index.json',
    );
    final graphJson = await rootBundle.loadString(
      'assets/data/nuuk_route_graph.json',
    );

    final searchData = jsonDecode(searchJson) as Map<String, Object?>;
    final graphData = jsonDecode(graphJson) as Map<String, Object?>;

    final entries = (searchData['entries'] as List<Object?>)
        .cast<Map<String, Object?>>()
        .map(OfflineSearchEntry.fromJson)
        .toList(growable: false);

    return OfflineDataRepository(
      entries: entries,
      router: OfflineRouter.fromJson(graphData),
    );
  }

  List<OfflineSearchResult> search(String query, {int limit = 12}) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) {
      return entries
          .where((entry) => entry.kind == 'store' || entry.kind == 'place')
          .take(limit)
          .map((entry) => OfflineSearchResult(entry: entry, score: 10))
          .toList(growable: false);
    }

    final terms = normalizedQuery.split(' ');
    final results = <OfflineSearchResult>[];

    for (final entry in entries) {
      if (!terms.every(entry.searchText.contains)) {
        continue;
      }

      results.add(
        OfflineSearchResult(
          entry: entry,
          score: _score(entry, normalizedQuery),
        ),
      );
    }

    results.sort((left, right) {
      final scoreCompare = right.score.compareTo(left.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return left.entry.label.compareTo(right.entry.label);
    });

    return results.take(limit).toList(growable: false);
  }

  int _score(OfflineSearchEntry entry, String query) {
    var score = 0;
    final normalizedLabel = _normalize(entry.label);
    final normalizedAddress = _normalize(entry.address);

    if (normalizedLabel == query) score += 100;
    if (normalizedLabel.startsWith(query)) score += 60;
    if (normalizedAddress.startsWith(query)) score += 40;
    if (entry.kind == 'store') score += 25;
    if (entry.kind == 'address' && entry.address.isNotEmpty) score += 15;
    if (entry.label.length <= 2 && entry.address.length <= 2) score -= 35;
    return score;
  }
}

int _groupSort(String group) {
  const order = {
    'Grocery': 0,
    'Food & Drink': 1,
    'Attractions': 2,
    'Transport': 3,
    'Services': 4,
    'Shopping': 5,
    'Places': 6,
  };
  return order[group] ?? 99;
}

String _normalize(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9æøå]+'), ' ').trim();
}
