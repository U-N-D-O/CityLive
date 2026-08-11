import 'package:latlong2/latlong.dart';

class NuukMap {
  static const westLongitude = -51.86;
  static const southLatitude = 64.10;
  static const eastLongitude = -51.57;
  static const northLatitude = 64.25;
  static const center = LatLng(64.17734, -51.68750);
  static const southWest = LatLng(southLatitude, westLongitude);
  static const northEast = LatLng(northLatitude, eastLongitude);
  static const centerLongitude = -51.68750;
  static const centerLatitude = 64.17734;
  static const initialZoom = 13.0;
  static const minZoom = 10.0;
  static const maxZoom = 17.5;
  static const rasterTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const vectorTileUrlPlaceholder =
      'http://localhost:8080/data/nuuk/{z}/{x}/{y}.pbf';
  static const vectorTileUrl = String.fromEnvironment(
    'NCL_VECTOR_TILE_URL',
    defaultValue: vectorTileUrlPlaceholder,
  );
  static const userAgentPackageName = 'com.nuukcitylive.app';

  static LatLng clampToBounds(LatLng point) {
    return LatLng(
      point.latitude.clamp(southLatitude, northLatitude),
      point.longitude.clamp(westLongitude, eastLongitude),
    );
  }
}
