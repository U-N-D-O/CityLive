# Nuuk City Live

Nuuk City Live is a Flutter/Dart app for navigation and local city information in Nuuk, Greenland. The first product target is a CarPlay-friendly driving experience, with the phone app providing the full map, store discovery, and transport options.

## Current Scope

- OpenStreetMap-based Nuuk map centered on the city.
- Store categories with an "open now" default view.
- Store detail sheet with image placeholder, opening hours, and one-tap local directions.
- Offline Nuuk address, street, and store search generated from the Greenland OSM extract.
- Offline Nuuk driving route graph generated from the same extract.
- Transport mode model for drive, bus, walk, taxi, and bike.
- CarPlay service contract so the iOS native CarPlay scene can sync route and place state later.

## Setup

The Dart package dependencies have been resolved. If `flutter` is not on your PATH, add the Flutter SDK `bin` folder and restart the terminal. Then run:

```powershell
flutter create . --project-name nuuk_city_live --platforms=ios,android
flutter pub get
flutter analyze
flutter test
```

The `flutter create` command will add the generated `ios/`, `android/`, and platform runner files around the existing Dart source.

Android debugging with MapLibre requires JDK 21. This machine has Temurin JDK 21 installed at `C:\Program Files\Eclipse Adoptium\jdk-21.0.12.8-hotspot`, and the VS Code F5 launch configs set `JAVA_HOME` to that path.

## OpenStreetMap Notes

The app uses MapLibre style JSON files that can be edited in Maputnik and centers on Nuuk at `64.17734, -51.68750`. The current styles expect vector tiles at `http://localhost:8080/data/nuuk/{z}/{x}/{y}.pbf`.

The latest Greenland OSM extract is expected at `greenland-260810.osm.pbf`. It is intentionally ignored by Git because map extracts and generated tile databases are large local build inputs.

### Offline Search And Routing Data

The app includes generated Nuuk-only JSON assets for offline search and local driving routes:

- `assets/data/nuuk_search_index.json`
- `assets/data/nuuk_route_graph.json`

Regenerate them after replacing the local PBF extract:

```powershell
npm install
npm run extract:nuuk
```

The extractor clips data to the Nuuk bounds in `tool/osm/extract_nuuk_offline_data.js`, so no addresses, stores, or route graph nodes outside Nuuk are suggested by the offline search path. The map camera is also constrained to the same city bounds in the app.

### Map Build Workflow

1. Install Docker Desktop.
2. In VS Code, run the task `Build Nuuk vector tiles from Greenland PBF`.
3. Run the task `Serve Nuuk vector tiles`.
4. Press F5 and choose `Nuuk City Live (Android Emulator - local tiles)` for an Android emulator, or `Nuuk City Live (host localhost tiles)` for a target that can access the host as `localhost`.

The tile build uses Planetiler in Docker and writes `build/maps/nuuk.mbtiles`. The tile server uses Tileserver GL and exposes the MapLibre URL above.

Windows debugging uses a raster OpenStreetMap fallback because the MapLibre Flutter plugin does not support Windows. The fallback applies the selected palette and dark/light tone as a visible tile treatment, while iOS and Android continue to use the Maputnik/MapLibre vector styles.

### Maputnik Styling

The four editable styles live in `assets/maps/styles/`:

- `blue_green_light.json`
- `blue_green_dark.json`
- `golden_grey_light.json`
- `golden_grey_dark.json`

Run one of these VS Code tasks to edit a style in Maputnik:

- `Open Maputnik - Blue Green Light`
- `Open Maputnik - Blue Green Dark`
- `Open Maputnik - Golden Grey Light`
- `Open Maputnik - Golden Grey Dark`

The current offline router is a small client-side route graph for Nuuk driving previews. Longer term, turn-by-turn guidance should add instruction generation or use an OSM-compatible routing engine such as OSRM, Valhalla, or GraphHopper with the same Nuuk extract.

## CarPlay Direction

Flutter handles the phone UI. CarPlay itself must be implemented in native iOS with Apple's CarPlay templates, then connected to Flutter through method channels. The Dart-side contract is in `lib/src/services/carplay_bridge.dart`.

This scaffold includes a native iOS CarPlay scene in `ios/Runner/CarPlaySceneDelegate.swift`. To test it in a real vehicle or CarPlay simulator later, the Apple developer account and app identifier must have the correct CarPlay entitlement, most likely the maps/navigation entitlement, and the iOS build must be run from macOS/Xcode.

## Next Technical Milestones

- Replace starter store records with verified Nuuk business data and locally owned images.
- Merge extracted OSM POIs into the curated store category sheets.
- Add live GPS location and turn instruction models.
- Expand CarPlay from the current list template to route guidance templates after entitlement approval.