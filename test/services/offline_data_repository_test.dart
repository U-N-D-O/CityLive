import 'package:flutter_test/flutter_test.dart';
import 'package:nuuk_city_live/src/constants/nuuk_map.dart';
import 'package:nuuk_city_live/src/services/offline_data_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads Nuuk-only offline search data and routes locally', () async {
    final repository = await OfflineDataRepository.load();
    final results = repository.search('Imaneq');

    expect(results, isNotEmpty);

    final route = repository.router.route(
      from: NuukMap.center,
      to: results.first.entry.coordinate,
    );

    expect(route, isNotNull);
    expect(route!.points.length, greaterThan(2));
    expect(route.distanceMeters, greaterThan(0));
  });

  test('classifies Nuuk grocery brands and convenience stores', () async {
    final repository = await OfflineDataRepository.load();

    for (final brand in ['Brugseni', 'Pisiffik', 'Akiki', 'nukøb']) {
      final results = repository.search(brand);
      expect(results, isNotEmpty, reason: brand);
      expect(results.first.entry.group, 'Grocery', reason: brand);
      expect(results.first.entry.subcategory, 'Grocery store', reason: brand);
      expect(results.first.entry.icon, 'grocery', reason: brand);
    }

    final convenienceStores = repository.placesForGroup(
      'Grocery',
      subcategory: 'Convenience store',
    );

    expect(convenienceStores, isNotEmpty);
    expect(convenienceStores.first.icon, 'convenience');
  });
}
