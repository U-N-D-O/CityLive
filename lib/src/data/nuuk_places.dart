import 'package:latlong2/latlong.dart';

import '../models/opening_hours.dart';
import '../models/place.dart';

const nuukPlaces = <Place>[
  Place(
    id: 'brugseni-nuuk',
    name: 'Brugseni Nuuk',
    category: PlaceCategory.groceries,
    coordinate: LatLng(64.175555, -51.737119),
    address: 'Brugseni Aqqusinersuaq 2',
    openingHours: OpeningHours(
      weekdayOpen: 8,
      weekdayClose: 21,
      saturdayOpen: 9,
      saturdayClose: 20,
      sundayOpen: 10,
      sundayClose: 18,
    ),
    imageUrl: 'assets/pictures/places/brugseni-nuuk.png',
    phone: '32 11 22',
  ),
  Place(
    id: 'pisiffik-nuuk-center',
    name: 'Pisiffik Nuuk Center',
    category: PlaceCategory.groceries,
    coordinate: LatLng(64.17595, -51.73793),
    address: 'Imaneq 1',
    openingHours: OpeningHours(
      weekdayOpen: 8,
      weekdayClose: 20,
      saturdayOpen: 9,
      saturdayClose: 18,
      sundayOpen: 10,
      sundayClose: 17,
    ),
    imageUrl: 'https://images.unsplash.com/photo-1542838132-92c53300491e',
  ),
  Place(
    id: 'inussivik-pharmacy',
    name: 'Nuuk Pharmacy',
    category: PlaceCategory.pharmacy,
    coordinate: LatLng(64.17656, -51.73705),
    address: 'Central Nuuk',
    openingHours: OpeningHours(
      weekdayOpen: 9,
      weekdayClose: 17,
      saturdayOpen: 10,
      saturdayClose: 14,
      sundayOpen: null,
      sundayClose: null,
    ),
    imageUrl: 'https://images.unsplash.com/photo-1587854692152-cbe660dbde88',
  ),
  Place(
    id: 'katuaq',
    name: 'Katuaq Culture Centre',
    category: PlaceCategory.culture,
    coordinate: LatLng(64.17678, -51.73831),
    address: 'Imaneq 21, Nuuk',
    openingHours: OpeningHours(
      weekdayOpen: 10,
      weekdayClose: 21,
      saturdayOpen: 10,
      saturdayClose: 21,
      sundayOpen: 12,
      sundayClose: 18,
    ),
    imageUrl: 'https://images.unsplash.com/photo-1518005020951-eccb494ad742',
  ),
  Place(
    id: 'nuuk-fuel-stop',
    name: 'Nuuk Fuel Stop',
    category: PlaceCategory.fuel,
    coordinate: LatLng(64.18321, -51.72191),
    address: 'Near airport road, Nuuk',
    openingHours: OpeningHours(
      weekdayOpen: 7,
      weekdayClose: 22,
      saturdayOpen: 8,
      saturdayClose: 22,
      sundayOpen: 8,
      sundayClose: 21,
    ),
    imageUrl: 'https://images.unsplash.com/photo-1545558014-8692077e9b5c',
  ),
];
