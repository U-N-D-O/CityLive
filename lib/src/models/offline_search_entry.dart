import 'package:latlong2/latlong.dart';

class OfflineSearchEntry {
  const OfflineSearchEntry({
    required this.id,
    required this.kind,
    required this.label,
    required this.category,
    required this.group,
    required this.subcategory,
    required this.icon,
    required this.address,
    required this.coordinate,
    required this.searchText,
  });

  final String id;
  final String kind;
  final String label;
  final String category;
  final String group;
  final String subcategory;
  final String icon;
  final String address;
  final LatLng coordinate;
  final String searchText;

  bool get isPlaceListing => group != 'Address';

  factory OfflineSearchEntry.fromJson(Map<String, Object?> json) {
    return OfflineSearchEntry(
      id: json['id'] as String,
      kind: json['kind'] as String,
      label: json['label'] as String,
      category: json['category'] as String,
      group:
          json['group'] as String? ?? _legacyGroup(json['category'] as String),
      subcategory: json['subcategory'] as String? ?? json['category'] as String,
      icon: json['icon'] as String? ?? 'place',
      address: json['address'] as String? ?? '',
      coordinate: LatLng(
        (json['latitude'] as num).toDouble(),
        (json['longitude'] as num).toDouble(),
      ),
      searchText: json['searchText'] as String,
    );
  }
}

String _legacyGroup(String category) {
  if (category == 'Address') return 'Address';
  if (category.startsWith('Shop: supermarket') ||
      category.startsWith('Shop: convenience')) {
    return 'Grocery';
  }
  if (category.startsWith('Tourism:')) return 'Attractions';
  if (category.startsWith('Amenity: restaurant') ||
      category.startsWith('Amenity: cafe') ||
      category.startsWith('Amenity: fast_food') ||
      category.startsWith('Amenity: bar')) {
    return 'Food & Drink';
  }
  if (category.startsWith('Shop:')) return 'Shopping';
  if (category.startsWith('Amenity:') || category.startsWith('Office:')) {
    return 'Services';
  }
  return 'Places';
}

class OfflineSearchResult {
  const OfflineSearchResult({required this.entry, required this.score});

  final OfflineSearchEntry entry;
  final int score;
}
