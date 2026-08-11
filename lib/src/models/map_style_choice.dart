import 'package:flutter/material.dart';

enum MapPalette {
  blueGreen('Blue Green'),
  goldenGrey('Golden Grey');

  const MapPalette(this.label);

  final String label;
}

enum MapTone {
  light('Light'),
  dark('Dark');

  const MapTone(this.label);

  final String label;
}

class NuukMapStyleChoice {
  const NuukMapStyleChoice({required this.palette, required this.tone});

  final MapPalette palette;
  final MapTone tone;

  String get id => '${palette.name}-${tone.name}';

  String get assetPath => switch ((palette, tone)) {
    (MapPalette.blueGreen, MapTone.light) =>
      'assets/maps/styles/blue_green_light.json',
    (MapPalette.blueGreen, MapTone.dark) =>
      'assets/maps/styles/blue_green_dark.json',
    (MapPalette.goldenGrey, MapTone.light) =>
      'assets/maps/styles/golden_grey_light.json',
    (MapPalette.goldenGrey, MapTone.dark) =>
      'assets/maps/styles/golden_grey_dark.json',
  };

  String get markerColor => switch (palette) {
    MapPalette.blueGreen => '#0B7A75',
    MapPalette.goldenGrey => '#A2772B',
  };

  Color get markerFlutterColor => switch (palette) {
    MapPalette.blueGreen => const Color(0xFF0B7A75),
    MapPalette.goldenGrey => const Color(0xFFA2772B),
  };

  Color get canvasColor => switch (tone) {
    MapTone.light => const Color(0xFFF4F1EA),
    MapTone.dark => const Color(0xFF151512),
  };
}
