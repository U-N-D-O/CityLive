import 'package:flutter_test/flutter_test.dart';
import 'package:nuuk_city_live/src/models/opening_hours.dart';

void main() {
  group('OpeningHours', () {
    const hours = OpeningHours(
      weekdayOpen: 8,
      weekdayClose: 17,
      saturdayOpen: 10,
      saturdayClose: 14,
    );

    test('reports open during weekday hours', () {
      expect(hours.isOpenAt(DateTime(2026, 8, 11, 12)), isTrue);
    });

    test('reports closed after weekday hours', () {
      expect(hours.isOpenAt(DateTime(2026, 8, 11, 19)), isFalse);
    });

    test('reports closed on Sunday when no Sunday hours are set', () {
      expect(hours.isOpenAt(DateTime(2026, 8, 16, 12)), isFalse);
    });
  });
}
