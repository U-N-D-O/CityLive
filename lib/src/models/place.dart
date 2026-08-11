import 'package:latlong2/latlong.dart';

import 'opening_hours.dart';

enum PlaceCategory {
  groceries('Groceries'),
  cafe('Cafes'),
  pharmacy('Pharmacies'),
  fuel('Fuel'),
  culture('Culture'),
  publicService('Public Service');

  const PlaceCategory(this.label);

  final String label;
}

class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.coordinate,
    required this.address,
    required this.openingHours,
    required this.imageUrl,
    this.phone,
  });

  final String id;
  final String name;
  final PlaceCategory category;
  final LatLng coordinate;
  final String address;
  final OpeningHours openingHours;
  final String imageUrl;
  final String? phone;

  bool isOpenAt(DateTime time) => openingHours.isOpenAt(time);
}
