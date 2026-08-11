import 'package:flutter/services.dart';

import '../models/place.dart';
import '../models/transport_mode.dart';

class CarPlayBridge {
  CarPlayBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('nuuk_city_live/carplay');

  final MethodChannel _channel;

  Future<void> activateNavigation({
    required Place destination,
    required TransportMode mode,
  }) async {
    await _invokeIfAvailable('activateNavigation', {
      'destinationId': destination.id,
      'destinationName': destination.name,
      'latitude': destination.coordinate.latitude,
      'longitude': destination.coordinate.longitude,
      'mode': mode.name,
    });
  }

  Future<void> updateVisiblePlaces(List<Place> places) async {
    await _invokeIfAvailable(
      'updateVisiblePlaces',
      places
          .map(
            (place) => {
              'id': place.id,
              'name': place.name,
              'category': place.category.name,
              'isOpen': place.isOpenAt(DateTime.now()),
              'latitude': place.coordinate.latitude,
              'longitude': place.coordinate.longitude,
            },
          )
          .toList(),
    );
  }

  Future<void> _invokeIfAvailable(String method, Object? arguments) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } on MissingPluginException {
      // The phone app can run before the native CarPlay scene is wired up.
    }
  }
}
