import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuuk_city_live/src/app.dart';

void main() {
  testWidgets('shows map-first floating controls', (tester) async {
    await tester.pumpWidget(const NuukCityLiveApp());

    expect(find.byIcon(Icons.tune), findsOneWidget);
    expect(find.byIcon(Icons.local_grocery_store), findsOneWidget);
    expect(find.byIcon(Icons.directions_car), findsOneWidget);
  });
}
