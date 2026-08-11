import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

import '../../constants/nuuk_map.dart';
import '../../data/nuuk_places.dart';
import '../../models/map_style_choice.dart';
import '../../models/offline_search_entry.dart';
import '../../models/place.dart';
import '../../models/transport_mode.dart';
import '../../services/carplay_bridge.dart';
import '../../services/offline_data_repository.dart';
import '../../services/offline_router.dart';

typedef NuukMapBuilder = Widget Function(BuildContext context);

class NuukHomePage extends StatefulWidget {
  const NuukHomePage({super.key, this.carPlayBridge, this.mapBuilder});

  final CarPlayBridge? carPlayBridge;
  final NuukMapBuilder? mapBuilder;

  @override
  State<NuukHomePage> createState() => _NuukHomePageState();
}

class _NuukHomePageState extends State<NuukHomePage> {
  TransportMode _selectedMode = TransportMode.drive;
  MapPalette _selectedPalette = MapPalette.blueGreen;
  MapTone _selectedTone = MapTone.light;
  _AppLanguage _selectedLanguage = _AppLanguage.english;
  bool _openNowOnly = true;
  int _recenterRequest = 0;
  LatLng _cameraTarget = NuukMap.center;
  LatLng? _currentLocation;
  final Set<String> _visibleMapGroups = <String>{};
  OfflineRoute? _activeRoute;
  OfflineSearchEntry? _activeDestination;
  StreamSubscription<Position>? _locationSubscription;
  late final CarPlayBridge _carPlayBridge;
  late final Future<OfflineDataRepository> _offlineDataFuture;

  NuukMapStyleChoice get _selectedMapStyle =>
      NuukMapStyleChoice(palette: _selectedPalette, tone: _selectedTone);

  @override
  void initState() {
    super.initState();
    _carPlayBridge = widget.carPlayBridge ?? CarPlayBridge();
    _offlineDataFuture = OfflineDataRepository.load();
    _carPlayBridge.updateVisiblePlaces(_visiblePlaces);
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  List<Place> get _visiblePlaces {
    final now = DateTime.now();
    return nuukPlaces.where((place) {
      final openMatches = !_openNowOnly || place.isOpenAt(now);
      return openMatches;
    }).toList();
  }

  List<OfflineSearchEntry> _mapEntries(OfflineDataRepository repository) {
    if (_visibleMapGroups.isEmpty) {
      return const [];
    }

    return repository.entries
        .where(
          (entry) =>
              entry.isPlaceListing && _visibleMapGroups.contains(entry.group),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final places = _visiblePlaces;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child:
                widget.mapBuilder?.call(context) ??
                FutureBuilder<OfflineDataRepository>(
                  future: _offlineDataFuture,
                  builder: (context, snapshot) {
                    final mapEntries = snapshot.data == null
                        ? const <OfflineSearchEntry>[]
                        : _mapEntries(snapshot.data!);

                    return _NuukMapView(
                      places: places,
                      mapEntries: mapEntries,
                      styleChoice: _selectedMapStyle,
                      cameraTarget: _cameraTarget,
                      recenterRequest: _recenterRequest,
                      routePoints: _activeRoute?.points ?? const [],
                      destination: _activeDestination?.coordinate,
                      destinationIcon: _activeDestination == null
                          ? null
                          : _iconForEntry(_activeDestination!),
                      currentLocation: _currentLocation,
                      onPlaceSelected: _showPlace,
                      onEntrySelected: _showOfflinePlace,
                      onMapLongPressed: _showDroppedPin,
                    );
                  },
                ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: _MapButton(
                      icon: Icons.tune,
                      tooltip: 'Settings',
                      onPressed: _showSettings,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _MapButton(
                        icon: Icons.search,
                        tooltip: 'Search Nuuk',
                        onPressed: _showSearch,
                      ),
                      const SizedBox(width: 12),
                      _PlacesClusterButton(onPressed: _showPlaces),
                      const Spacer(),
                      _MapButton(
                        icon: _selectedMode.icon,
                        tooltip: _selectedMode.label,
                        onPressed: _showTransportModes,
                      ),
                      const SizedBox(width: 12),
                      _MapButton(
                        icon: Icons.my_location,
                        tooltip: _selectedLanguage.myLocation,
                        onPressed: _recenterMap,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _setOpenNowOnly(bool value) {
    setState(() => _openNowOnly = value);
    _carPlayBridge.updateVisiblePlaces(_visiblePlaces);
  }

  void _setMode(TransportMode mode) {
    setState(() => _selectedMode = mode);
  }

  void _setPalette(MapPalette palette) {
    setState(() => _selectedPalette = palette);
  }

  void _setTone(MapTone tone) {
    setState(() => _selectedTone = tone);
  }

  void _setLanguage(_AppLanguage language) {
    setState(() => _selectedLanguage = language);
  }

  void _setMapGroupVisible(String group, bool visible) {
    setState(() {
      if (visible) {
        _visibleMapGroups.add(group);
      } else {
        _visibleMapGroups.remove(group);
      }
    });
  }

  Future<void> _recenterMap() async {
    if (_currentLocation == null) {
      await _startLocationUpdates(showErrors: true);
    }

    setState(() {
      _cameraTarget = _currentLocation ?? NuukMap.center;
      _activeRoute = null;
      _activeDestination = null;
      _recenterRequest++;
    });
  }

  LatLng? get _routeOrigin => _currentLocation;

  void _showSearch() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _OfflineSearchSheet(
        offlineDataFuture: _offlineDataFuture,
        onSelected: _focusSearchEntry,
      ),
    );
  }

  void _showSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SettingsSheet(
        selectedPalette: _selectedPalette,
        selectedTone: _selectedTone,
        selectedLanguage: _selectedLanguage,
        selectedMode: _selectedMode,
        openNowOnly: _openNowOnly,
        usesDesktopMapFallback: _usesDesktopMapFallback,
        onPaletteChanged: _setPalette,
        onToneChanged: _setTone,
        onLanguageChanged: _setLanguage,
        onModeChanged: _setMode,
        onOpenNowChanged: _setOpenNowOnly,
      ),
    );
  }

  void _showPlaces() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PlacesSheet(
        offlineDataFuture: _offlineDataFuture,
        visibleMapGroups: _visibleMapGroups,
        onMapGroupVisibilityChanged: _setMapGroupVisible,
        onPlaceSelected: _focusSearchEntry,
      ),
    );
  }

  void _showTransportModes() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _TransportSheet(selectedMode: _selectedMode, onModeChanged: _setMode),
    );
  }

  void _showPlace(Place place) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _PlaceSheet(
        place: place,
        selectedMode: _selectedMode,
        onStartNavigation: () => _startNavigation(place),
      ),
    );
  }

  void _showOfflinePlace(OfflineSearchEntry entry) {
    final curatedPlace = _curatedPlaceForEntry(entry);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _OfflineEntrySheet(
        entry: entry,
        curatedPlace: curatedPlace,
        selectedMode: _selectedMode,
        onStartNavigation: () => _goToEntry(entry),
      ),
    );
  }

  void _showDroppedPin(LatLng coordinate) {
    final clamped = NuukMap.clampToBounds(coordinate);
    final entry = OfflineSearchEntry(
      id: 'pin-${clamped.latitude.toStringAsFixed(5)}-${clamped.longitude.toStringAsFixed(5)}',
      kind: 'pin',
      label: 'Dropped pin',
      category: 'Map point',
      group: 'Places',
      subcategory: 'Map point',
      icon: 'pin',
      address:
          '${clamped.latitude.toStringAsFixed(5)}, ${clamped.longitude.toStringAsFixed(5)}',
      coordinate: clamped,
      searchText: 'dropped pin',
    );

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _OfflineEntrySheet(
        entry: entry,
        selectedMode: _selectedMode,
        onStartNavigation: () => _goToEntry(entry),
      ),
    );
  }

  Future<void> _focusSearchEntry(OfflineSearchEntry entry) async {
    await _goToEntry(entry);
  }

  Future<void> _goToEntry(
    OfflineSearchEntry entry, {
    bool closeCurrentSheet = true,
  }) async {
    if (closeCurrentSheet && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    final repository = await _offlineDataFuture;
    final origin = _routeOrigin;
    final route = origin == null
        ? null
        : repository.router.route(from: origin, to: entry.coordinate);

    if (!mounted) {
      return;
    }

    setState(() {
      _cameraTarget = entry.coordinate;
      _activeRoute = route;
      _activeDestination = entry;
      _recenterRequest++;
    });

    _showRouteMessage(route, entry.label, hasOrigin: origin != null);
  }

  Place? _curatedPlaceForEntry(OfflineSearchEntry entry) {
    for (final place in nuukPlaces) {
      if (place.id == entry.id) {
        return place;
      }
    }

    final normalizedEntry = _normalizeLabel(entry.label);
    for (final place in nuukPlaces) {
      if (_normalizeLabel(place.name) == normalizedEntry) {
        return place;
      }
    }

    return null;
  }

  Future<void> _startNavigation(Place place) async {
    await _carPlayBridge.activateNavigation(
      destination: place,
      mode: _selectedMode,
    );

    final repository = await _offlineDataFuture;
    final origin = _routeOrigin;
    final route = origin == null
        ? null
        : repository.router.route(from: origin, to: place.coordinate);

    if (!mounted) {
      return;
    }

    setState(() {
      _cameraTarget = place.coordinate;
      _activeRoute = route;
      _activeDestination = OfflineSearchEntry(
        id: place.id,
        kind: 'store',
        label: place.name,
        category: place.category.label,
        group: place.category.label,
        subcategory: place.category.label,
        icon: place.category.iconKey,
        address: place.address,
        coordinate: place.coordinate,
        searchText: place.name.toLowerCase(),
      );
      _recenterRequest++;
    });

    _showRouteMessage(route, place.name, hasOrigin: origin != null);
  }

  void _showRouteMessage(
    OfflineRoute? route,
    String destination, {
    required bool hasOrigin,
  }) {
    final message = !hasOrigin
        ? 'Turn on location access to route from your real position.'
        : route == null
        ? 'No local driving route found to $destination'
        : '${(route.distanceMeters / 1000).toStringAsFixed(1)} km local route to $destination';

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startLocationUpdates({bool showErrors = false}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (showErrors && mounted) {
          _showLocationMessage(
            'Turn on Location Services to route from your current position.',
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (showErrors && mounted) {
          _showLocationMessage(
            'Allow location access to route from your current position.',
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      );
      _applyPosition(position);

      _locationSubscription ??= Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 5,
        ),
      ).listen(_applyPosition);
    } on Exception {
      if (showErrors && mounted) {
        _showLocationMessage(
          'Location is not available yet. Try again when GPS has a fix.',
        );
      }
    }
  }

  void _applyPosition(Position position) {
    final coordinate = LatLng(position.latitude, position.longitude);
    if (!NuukMap.contains(coordinate)) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _currentLocation = coordinate;
    });
  }

  void _showLocationMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _NuukMapView extends StatelessWidget {
  const _NuukMapView({
    required this.places,
    required this.mapEntries,
    required this.styleChoice,
    required this.cameraTarget,
    required this.recenterRequest,
    required this.routePoints,
    required this.destination,
    required this.destinationIcon,
    required this.currentLocation,
    required this.onPlaceSelected,
    required this.onEntrySelected,
    required this.onMapLongPressed,
  });

  final List<Place> places;
  final List<OfflineSearchEntry> mapEntries;
  final NuukMapStyleChoice styleChoice;
  final LatLng cameraTarget;
  final int recenterRequest;
  final List<LatLng> routePoints;
  final LatLng? destination;
  final IconData? destinationIcon;
  final LatLng? currentLocation;
  final ValueChanged<Place> onPlaceSelected;
  final ValueChanged<OfflineSearchEntry> onEntrySelected;
  final ValueChanged<LatLng> onMapLongPressed;

  @override
  Widget build(BuildContext context) {
    if (_usesDesktopMapFallback) {
      return _NuukDesktopMapView(
        places: places,
        mapEntries: mapEntries,
        styleChoice: styleChoice,
        cameraTarget: cameraTarget,
        recenterRequest: recenterRequest,
        routePoints: routePoints,
        destination: destination,
        destinationIcon: destinationIcon,
        currentLocation: currentLocation,
        onPlaceSelected: onPlaceSelected,
        onEntrySelected: onEntrySelected,
        onMapLongPressed: onMapLongPressed,
      );
    }

    return _NuukMapLibreView(
      places: places,
      mapEntries: mapEntries,
      styleChoice: styleChoice,
      cameraTarget: cameraTarget,
      recenterRequest: recenterRequest,
      routePoints: routePoints,
      destination: destination,
      destinationIcon: destinationIcon,
      currentLocation: currentLocation,
      onPlaceSelected: onPlaceSelected,
      onEntrySelected: onEntrySelected,
      onMapLongPressed: onMapLongPressed,
    );
  }
}

class _NuukDesktopMapView extends StatefulWidget {
  const _NuukDesktopMapView({
    required this.places,
    required this.mapEntries,
    required this.styleChoice,
    required this.cameraTarget,
    required this.recenterRequest,
    required this.routePoints,
    required this.destination,
    required this.destinationIcon,
    required this.currentLocation,
    required this.onPlaceSelected,
    required this.onEntrySelected,
    required this.onMapLongPressed,
  });

  final List<Place> places;
  final List<OfflineSearchEntry> mapEntries;
  final NuukMapStyleChoice styleChoice;
  final LatLng cameraTarget;
  final int recenterRequest;
  final List<LatLng> routePoints;
  final LatLng? destination;
  final IconData? destinationIcon;
  final LatLng? currentLocation;
  final ValueChanged<Place> onPlaceSelected;
  final ValueChanged<OfflineSearchEntry> onEntrySelected;
  final ValueChanged<LatLng> onMapLongPressed;

  @override
  State<_NuukDesktopMapView> createState() => _NuukDesktopMapViewState();
}

class _NuukDesktopMapViewState extends State<_NuukDesktopMapView> {
  final _mapController = fm.MapController();

  @override
  void didUpdateWidget(_NuukDesktopMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recenterRequest != widget.recenterRequest) {
      _mapController.move(widget.cameraTarget, NuukMap.initialZoom + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return fm.FlutterMap(
      mapController: _mapController,
      options: fm.MapOptions(
        initialCenter: NuukMap.center,
        initialZoom: NuukMap.initialZoom,
        minZoom: NuukMap.minZoom,
        maxZoom: NuukMap.maxZoom,
        cameraConstraint: fm.CameraConstraint.containCenter(
          bounds: fm.LatLngBounds(NuukMap.southWest, NuukMap.northEast),
        ),
        onLongPress: (_, point) => widget.onMapLongPressed(point),
      ),
      children: [
        fm.TileLayer(
          urlTemplate: NuukMap.rasterTileUrl,
          userAgentPackageName: NuukMap.userAgentPackageName,
          tileBuilder: widget.styleChoice.rasterTileBuilder,
        ),
        if (widget.routePoints.length > 1)
          fm.PolylineLayer(
            polylines: [
              fm.Polyline(
                points: widget.routePoints,
                color: widget.styleChoice.markerFlutterColor,
                strokeWidth: 5,
                borderColor: Colors.white,
                borderStrokeWidth: 2,
              ),
            ],
          ),
        fm.MarkerLayer(
          markers: [
            if (widget.currentLocation != null)
              fm.Marker(
                point: widget.currentLocation!,
                width: 44,
                height: 44,
                child: _CarMarker(color: widget.styleChoice.markerFlutterColor),
              ),
            if (widget.destination != null)
              fm.Marker(
                point: widget.destination!,
                width: 42,
                height: 42,
                child: _DestinationMarker(
                  color: widget.styleChoice.markerFlutterColor,
                  icon: widget.destinationIcon ?? Icons.near_me,
                ),
              ),
            for (final place in widget.places)
              fm.Marker(
                point: place.coordinate,
                width: 38,
                height: 38,
                child: _PlaceMarker(
                  color: widget.styleChoice.markerFlutterColor,
                  icon: place.category.icon,
                  onTap: () => widget.onPlaceSelected(place),
                ),
              ),
            for (final entry in widget.mapEntries)
              fm.Marker(
                point: entry.coordinate,
                width: 38,
                height: 38,
                child: _PlaceMarker(
                  color: widget.styleChoice.markerFlutterColor,
                  icon: _iconForEntry(entry),
                  onTap: () => widget.onEntrySelected(entry),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _NuukMapLibreView extends StatefulWidget {
  const _NuukMapLibreView({
    required this.places,
    required this.mapEntries,
    required this.styleChoice,
    required this.cameraTarget,
    required this.recenterRequest,
    required this.routePoints,
    required this.destination,
    required this.destinationIcon,
    required this.currentLocation,
    required this.onPlaceSelected,
    required this.onEntrySelected,
    required this.onMapLongPressed,
  });

  final List<Place> places;
  final List<OfflineSearchEntry> mapEntries;
  final NuukMapStyleChoice styleChoice;
  final LatLng cameraTarget;
  final int recenterRequest;
  final List<LatLng> routePoints;
  final LatLng? destination;
  final IconData? destinationIcon;
  final LatLng? currentLocation;
  final ValueChanged<Place> onPlaceSelected;
  final ValueChanged<OfflineSearchEntry> onEntrySelected;
  final ValueChanged<LatLng> onMapLongPressed;

  @override
  State<_NuukMapLibreView> createState() => _NuukMapLibreViewState();
}

class _NuukMapLibreViewState extends State<_NuukMapLibreView> {
  ml.MapLibreMapController? _controller;
  String? _styleJson;
  int _styleLoadGeneration = 0;
  final Set<String> _registeredMarkerImages = {};

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  @override
  void didUpdateWidget(_NuukMapLibreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.styleChoice.id != widget.styleChoice.id) {
      _loadStyle();
      return;
    }

    if (oldWidget.places != widget.places ||
        oldWidget.mapEntries != widget.mapEntries) {
      _syncMapAnnotations();
    }

    if (oldWidget.routePoints != widget.routePoints ||
        oldWidget.destination != widget.destination ||
        oldWidget.destinationIcon != widget.destinationIcon ||
        oldWidget.currentLocation != widget.currentLocation) {
      _syncMapAnnotations();
    }

    if (oldWidget.recenterRequest != widget.recenterRequest) {
      _recenterMap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final styleJson = _styleJson;
    if (styleJson == null) {
      return ColoredBox(
        color: widget.styleChoice.canvasColor,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return ml.MapLibreMap(
      key: ValueKey(widget.styleChoice.id),
      styleString: styleJson,
      initialCameraPosition: const ml.CameraPosition(
        target: ml.LatLng(NuukMap.centerLatitude, NuukMap.centerLongitude),
        zoom: NuukMap.initialZoom,
      ),
      minMaxZoomPreference: const ml.MinMaxZoomPreference(
        NuukMap.minZoom,
        NuukMap.maxZoom,
      ),
      cameraTargetBounds: ml.CameraTargetBounds(
        ml.LatLngBounds(
          southwest: const ml.LatLng(
            NuukMap.southLatitude,
            NuukMap.westLongitude,
          ),
          northeast: const ml.LatLng(
            NuukMap.northLatitude,
            NuukMap.eastLongitude,
          ),
        ),
      ),
      compassEnabled: false,
      iosLongClickDuration: const Duration(milliseconds: 500),
      myLocationEnabled: true,
      attributionButtonPosition: ml.AttributionButtonPosition.bottomLeft,
      onMapLongClick: (_, coordinate) => widget.onMapLongPressed(
        LatLng(coordinate.latitude, coordinate.longitude),
      ),
      onMapCreated: (controller) {
        _controller = controller;
        controller.onSymbolTapped.add(_handleSymbolTapped);
      },
      onStyleLoadedCallback: _syncMapAnnotations,
    );
  }

  @override
  void dispose() {
    _controller?.onSymbolTapped.remove(_handleSymbolTapped);
    super.dispose();
  }

  Future<void> _loadStyle() async {
    final generation = ++_styleLoadGeneration;
    final style = NuukMap.usesDefaultVectorTileUrl
        ? widget.styleChoice.mapLibreRasterStyleJson
        : await rootBundle.loadString(widget.styleChoice.assetPath);
    if (!mounted || generation != _styleLoadGeneration) {
      return;
    }

    _registeredMarkerImages.clear();
    setState(() {
      _styleJson = style.replaceAll(
        NuukMap.vectorTileUrlPlaceholder,
        NuukMap.vectorTileUrl,
      );
    });
  }

  Future<void> _syncMapAnnotations() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    await controller.clearLines();
    await controller.clearSymbols();
    if (widget.routePoints.length > 1) {
      await controller.addLine(
        ml.LineOptions(
          geometry: widget.routePoints
              .map((point) => ml.LatLng(point.latitude, point.longitude))
              .toList(growable: false),
          lineColor: widget.styleChoice.markerColor,
          lineWidth: 5,
          lineOpacity: 0.92,
        ),
      );
    }

    if (widget.currentLocation != null) {
      await _addMapSymbol(
        controller: controller,
        point: widget.currentLocation!,
        icon: Icons.directions_car,
        color: widget.styleChoice.markerFlutterColor,
        selected: true,
      );
    }

    if (widget.destination != null) {
      await _addMapSymbol(
        controller: controller,
        point: widget.destination!,
        icon: widget.destinationIcon ?? Icons.near_me,
        color: widget.styleChoice.markerFlutterColor,
        selected: true,
      );
    }

    for (final place in widget.places) {
      await _addMapSymbol(
        controller: controller,
        point: place.coordinate,
        icon: place.category.icon,
        color: widget.styleChoice.markerFlutterColor,
      );
    }

    for (final entry in widget.mapEntries) {
      await _addMapSymbol(
        controller: controller,
        point: entry.coordinate,
        icon: _iconForEntry(entry),
        color: widget.styleChoice.markerFlutterColor,
      );
    }
  }

  Future<void> _addMapSymbol({
    required ml.MapLibreMapController controller,
    required LatLng point,
    required IconData icon,
    required Color color,
    bool selected = false,
  }) async {
    final imageName = _mapIconImageName(icon, color, selected: selected);
    if (_registeredMarkerImages.add(imageName)) {
      await controller.addImage(
        imageName,
        await _markerImageBytes(icon, color, selected: selected),
      );
    }

    await controller.addSymbol(
      ml.SymbolOptions(
        geometry: ml.LatLng(point.latitude, point.longitude),
        iconImage: imageName,
        iconSize: 1,
        iconAnchor: 'bottom',
      ),
    );
  }

  Future<void> _recenterMap() async {
    await _controller?.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(
          target: ml.LatLng(
            NuukMap.clampToBounds(widget.cameraTarget).latitude,
            NuukMap.clampToBounds(widget.cameraTarget).longitude,
          ),
          zoom: NuukMap.initialZoom + 1,
        ),
      ),
    );
  }

  void _handleSymbolTapped(ml.Symbol symbol) {
    final tappedGeometry = symbol.options.geometry;
    if (tappedGeometry == null) {
      return;
    }

    for (final place in widget.places) {
      if ((place.coordinate.latitude - tappedGeometry.latitude).abs() <
              0.0001 &&
          (place.coordinate.longitude - tappedGeometry.longitude).abs() <
              0.0001) {
        widget.onPlaceSelected(place);
        return;
      }
    }

    for (final entry in widget.mapEntries) {
      if ((entry.coordinate.latitude - tappedGeometry.latitude).abs() <
              0.0001 &&
          (entry.coordinate.longitude - tappedGeometry.longitude).abs() <
              0.0001) {
        widget.onEntrySelected(entry);
        return;
      }
    }
  }
}

class _OfflineSearchSheet extends StatefulWidget {
  const _OfflineSearchSheet({
    required this.offlineDataFuture,
    required this.onSelected,
  });

  final Future<OfflineDataRepository> offlineDataFuture;
  final ValueChanged<OfflineSearchEntry> onSelected;

  @override
  State<_OfflineSearchSheet> createState() => _OfflineSearchSheetState();
}

class _OfflineSearchSheetState extends State<_OfflineSearchSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.74,
        child: FutureBuilder<OfflineDataRepository>(
          future: widget.offlineDataFuture,
          builder: (context, snapshot) {
            final repository = snapshot.data;
            final results = repository?.search(_query) ?? const [];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SheetTitle(
                  title: 'Search Nuuk',
                  subtitle: 'Addresses, streets, and stores work offline',
                ),
                TextField(
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Street, address, or store',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 14),
                if (repository == null)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Expanded(
                    child: results.isEmpty
                        ? const Center(child: Text('No Nuuk result found'))
                        : ListView.separated(
                            itemBuilder: (context, index) {
                              final result = results[index].entry;
                              return _SearchResultTile(
                                entry: result,
                                onTap: () => widget.onSelected(result),
                              );
                            },
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemCount: results.length,
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.entry, required this.onTap});

  final OfflineSearchEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F6F5),
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(_iconForEntry(entry)),
        title: Text(
          entry.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            entry.category,
            entry.address,
          ].where((value) => value.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.near_me),
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xEE101820),
      elevation: 6,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(8),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        color: Colors.white,
        icon: Icon(icon),
      ),
    );
  }
}

class _PlacesClusterButton extends StatelessWidget {
  const _PlacesClusterButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xEE101820),
      elevation: 6,
      shadowColor: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                Icon(Icons.local_grocery_store, color: Colors.white, size: 14),
                Icon(Icons.restaurant, color: Colors.white, size: 14),
                Icon(Icons.museum, color: Colors.white, size: 14),
                Icon(Icons.place, color: Colors.white, size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CarMarker extends StatelessWidget {
  const _CarMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xEE101820),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: const Icon(Icons.directions_car, color: Colors.white, size: 22),
    );
  }
}

class _PlaceMarker extends StatelessWidget {
  const _PlaceMarker({
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _DestinationMarker extends StatelessWidget {
  const _DestinationMarker({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({
    required this.selectedPalette,
    required this.selectedTone,
    required this.selectedLanguage,
    required this.selectedMode,
    required this.openNowOnly,
    required this.usesDesktopMapFallback,
    required this.onPaletteChanged,
    required this.onToneChanged,
    required this.onLanguageChanged,
    required this.onModeChanged,
    required this.onOpenNowChanged,
  });

  final MapPalette selectedPalette;
  final MapTone selectedTone;
  final _AppLanguage selectedLanguage;
  final TransportMode selectedMode;
  final bool openNowOnly;
  final bool usesDesktopMapFallback;
  final ValueChanged<MapPalette> onPaletteChanged;
  final ValueChanged<MapTone> onToneChanged;
  final ValueChanged<_AppLanguage> onLanguageChanged;
  final ValueChanged<TransportMode> onModeChanged;
  final ValueChanged<bool> onOpenNowChanged;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTitle(title: 'Settings', subtitle: 'Map and route defaults'),
          _OptionGroup(
            label: 'Style',
            child: SegmentedButton<MapPalette>(
              segments: [
                for (final palette in MapPalette.values)
                  ButtonSegment(value: palette, label: Text(palette.label)),
              ],
              selected: {selectedPalette},
              onSelectionChanged: (selection) =>
                  onPaletteChanged(selection.first),
            ),
          ),
          _OptionGroup(
            label: 'Tone',
            child: SegmentedButton<MapTone>(
              segments: [
                for (final tone in MapTone.values)
                  ButtonSegment(value: tone, label: Text(tone.label)),
              ],
              selected: {selectedTone},
              onSelectionChanged: (selection) => onToneChanged(selection.first),
            ),
          ),
          _OptionGroup(
            label: 'Language',
            child: SegmentedButton<_AppLanguage>(
              segments: [
                for (final language in _AppLanguage.values)
                  ButtonSegment(value: language, label: Text(language.label)),
              ],
              selected: {selectedLanguage},
              onSelectionChanged: (selection) =>
                  onLanguageChanged(selection.first),
            ),
          ),
          _OptionGroup(
            label: 'Transport',
            child: DropdownButtonFormField<TransportMode>(
              initialValue: selectedMode,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                for (final mode in TransportMode.values)
                  DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  onModeChanged(mode);
                }
              },
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show open places first'),
            subtitle: const Text('Hide closed stores in the quick list'),
            value: openNowOnly,
            onChanged: onOpenNowChanged,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.map_outlined),
            title: Text(
              usesDesktopMapFallback ? 'Desktop debug map' : 'MapLibre map',
            ),
            subtitle: Text(
              usesDesktopMapFallback
                  ? 'Windows uses a raster fallback because MapLibre does not support Windows.'
                  : 'iOS and Android use the Maputnik styles and vector tiles.',
            ),
          ),
        ],
      ),
    );
  }
}

class _PlacesSheet extends StatefulWidget {
  const _PlacesSheet({
    required this.onPlaceSelected,
    required this.offlineDataFuture,
    required this.visibleMapGroups,
    required this.onMapGroupVisibilityChanged,
  });

  final Future<OfflineDataRepository> offlineDataFuture;
  final Set<String> visibleMapGroups;
  final void Function(String group, bool visible) onMapGroupVisibilityChanged;
  final ValueChanged<OfflineSearchEntry> onPlaceSelected;

  @override
  State<_PlacesSheet> createState() => _PlacesSheetState();
}

class _PlacesSheetState extends State<_PlacesSheet> {
  String? _selectedGroup;
  String? _selectedSubcategory;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.68,
        child: FutureBuilder<OfflineDataRepository>(
          future: widget.offlineDataFuture,
          builder: (context, snapshot) {
            final repository = snapshot.data;
            if (repository == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final selectedGroup = _selectedGroup;
            final places = selectedGroup == null
                ? const <OfflineSearchEntry>[]
                : repository.placesForGroup(
                    selectedGroup,
                    subcategory: _selectedSubcategory,
                  );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SheetTitle(
                  title: 'Places',
                  subtitle: selectedGroup ?? 'Choose a category',
                ),
                if (selectedGroup == null)
                  Expanded(
                    child: GridView.count(
                      crossAxisCount: MediaQuery.sizeOf(context).width > 700
                          ? 3
                          : 2,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.45,
                      children: [
                        for (final group in repository.placeGroups)
                          _PlaceGroupCard(
                            group: group,
                            count: repository.placesForGroup(group).length,
                            visibleOnMap: widget.visibleMapGroups.contains(
                              group,
                            ),
                            onVisibilityChanged: (visible) => widget
                                .onMapGroupVisibilityChanged(group, visible),
                            onTap: () => setState(() {
                              _selectedGroup = group;
                              _selectedSubcategory = null;
                            }),
                          ),
                      ],
                    ),
                  )
                else ...[
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _selectedGroup = null;
                          _selectedSubcategory = null;
                        }),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Categories'),
                      ),
                    ],
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _selectedSubcategory == null,
                          onSelected: (_) =>
                              setState(() => _selectedSubcategory = null),
                        ),
                        const SizedBox(width: 8),
                        for (final subcategory
                            in repository.subcategoriesForGroup(
                              selectedGroup,
                            )) ...[
                          ChoiceChip(
                            avatar: Icon(
                              _iconForSubcategory(selectedGroup, subcategory),
                              size: 18,
                            ),
                            label: Text(subcategory),
                            selected: _selectedSubcategory == subcategory,
                            onSelected: (_) => setState(
                              () => _selectedSubcategory = subcategory,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: places.isEmpty
                        ? const Center(
                            child: Text('No places in this category'),
                          )
                        : ListView.separated(
                            itemBuilder: (context, index) {
                              final place = places[index];
                              return _OfflinePlaceTile(
                                entry: place,
                                onTap: () => widget.onPlaceSelected(place),
                              );
                            },
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemCount: places.length,
                          ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PlaceGroupCard extends StatelessWidget {
  const _PlaceGroupCard({
    required this.group,
    required this.count,
    required this.visibleOnMap,
    required this.onVisibilityChanged,
    required this.onTap,
  });

  final String group;
  final int count;
  final bool visibleOnMap;
  final ValueChanged<bool> onVisibilityChanged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F6F5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFF101820),
                foregroundColor: Colors.white,
                child: Icon(_iconForGroup(group), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text('$count places'),
                  ],
                ),
              ),
              IconButton(
                tooltip: visibleOnMap ? 'Hide on map' : 'Show on map',
                onPressed: () => onVisibilityChanged(!visibleOnMap),
                icon: Icon(
                  visibleOnMap ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransportSheet extends StatelessWidget {
  const _TransportSheet({
    required this.selectedMode,
    required this.onModeChanged,
  });

  final TransportMode selectedMode;
  final ValueChanged<TransportMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetTitle(title: 'Route', subtitle: 'Choose how to get there'),
          for (final mode in TransportMode.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(mode.icon),
              title: Text(mode.label),
              subtitle: Text(mode.description),
              trailing: selectedMode == mode ? const Icon(Icons.check) : null,
              onTap: () {
                onModeChanged(mode);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _OfflinePlaceTile extends StatelessWidget {
  const _OfflinePlaceTile({required this.entry, required this.onTap});

  final OfflineSearchEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F6F5),
      borderRadius: BorderRadius.circular(8),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Icon(_iconForEntry(entry)),
        title: Text(
          entry.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            entry.subcategory,
            entry.address,
          ].where((value) => value.isNotEmpty).join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _PlaceSheet extends StatelessWidget {
  const _PlaceSheet({
    required this.place,
    required this.selectedMode,
    required this.onStartNavigation,
  });

  final Place place;
  final TransportMode selectedMode;
  final VoidCallback onStartNavigation;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 7,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _PlaceImage(path: place.imageUrl),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            place.name,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(place.address),
          const SizedBox(height: 10),
          Text(place.openingHours.summary),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStartNavigation,
              icon: Icon(selectedMode.icon),
              label: const Text('Go'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineEntrySheet extends StatelessWidget {
  const _OfflineEntrySheet({
    required this.entry,
    required this.selectedMode,
    required this.onStartNavigation,
    this.curatedPlace,
  });

  final OfflineSearchEntry entry;
  final Place? curatedPlace;
  final TransportMode selectedMode;
  final VoidCallback onStartNavigation;

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (curatedPlace != null) ...[
            AspectRatio(
              aspectRatio: 16 / 7,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _PlaceImage(path: curatedPlace!.imageUrl),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            entry.label,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(entry.address.isEmpty ? entry.category : entry.address),
          const SizedBox(height: 10),
          Text(
            curatedPlace?.openingHours.summary ?? 'Opening hours not added yet',
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onStartNavigation,
              icon: Icon(selectedMode.icon),
              label: const Text('Go'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceImage extends StatelessWidget {
  const _PlaceImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final trimmedPath = path.trim();
    if (trimmedPath.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;
      return ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: colorScheme.onSurfaceVariant,
          size: 38,
        ),
      );
    }

    if (trimmedPath.startsWith('assets/')) {
      return Image.asset(trimmedPath, fit: BoxFit.cover);
    }

    return Image.network(trimmedPath, fit: BoxFit.cover);
  }
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: child,
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _OptionGroup extends StatelessWidget {
  const _OptionGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

bool get _usesDesktopMapFallback {
  if (kIsWeb) {
    return false;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.macOS => true,
    _ => false,
  };
}

enum _AppLanguage {
  english('English', 'My location'),
  greenlandic('Kalaallisut', 'Sumiiffiga');

  const _AppLanguage(this.label, this.myLocation);

  final String label;
  final String myLocation;
}

extension on TransportMode {
  IconData get icon => switch (this) {
    TransportMode.drive => Icons.directions_car,
    TransportMode.bus => Icons.directions_bus,
    TransportMode.walk => Icons.directions_walk,
    TransportMode.taxi => Icons.local_taxi,
    TransportMode.bike => Icons.directions_bike,
  };
}

extension on PlaceCategory {
  IconData get icon => switch (this) {
    PlaceCategory.groceries => Icons.local_grocery_store,
    PlaceCategory.cafe => Icons.local_cafe,
    PlaceCategory.pharmacy => Icons.local_pharmacy,
    PlaceCategory.fuel => Icons.local_gas_station,
    PlaceCategory.culture => Icons.museum,
    PlaceCategory.publicService => Icons.account_balance,
  };

  String get iconKey => switch (this) {
    PlaceCategory.groceries => 'grocery',
    PlaceCategory.cafe => 'cafe',
    PlaceCategory.pharmacy => 'service',
    PlaceCategory.fuel => 'fuel',
    PlaceCategory.culture => 'museum',
    PlaceCategory.publicService => 'service',
  };
}

IconData _iconForEntry(OfflineSearchEntry entry) {
  return switch (entry.icon) {
    'grocery' => Icons.local_grocery_store,
    'convenience' => Icons.local_convenience_store,
    'restaurant' => Icons.restaurant,
    'cafe' => Icons.local_cafe,
    'museum' => Icons.museum,
    'attraction' => Icons.attractions,
    'fuel' => Icons.local_gas_station,
    'transport' => Icons.directions_bus,
    'service' => Icons.account_balance,
    'shop' => Icons.storefront,
    'address' => Icons.home,
    'pin' => Icons.location_pin,
    _ => Icons.place,
  };
}

IconData _iconForGroup(String group) {
  return switch (group) {
    'Grocery' => Icons.local_grocery_store,
    'Food & Drink' => Icons.restaurant,
    'Attractions' => Icons.museum,
    'Transport' => Icons.directions_bus,
    'Services' => Icons.account_balance,
    'Shopping' => Icons.storefront,
    _ => Icons.place,
  };
}

IconData _iconForSubcategory(String group, String subcategory) {
  if (group == 'Grocery' && subcategory == 'Convenience store') {
    return Icons.local_convenience_store;
  }
  if (group == 'Grocery') {
    return Icons.local_grocery_store;
  }
  return _iconForGroup(group);
}

extension on NuukMapStyleChoice {
  String get mapLibreRasterStyleJson {
    final background = tone == MapTone.dark ? '#111412' : '#F4F1EA';
    final opacity = tone == MapTone.dark ? 0.74 : 0.92;

    return jsonEncode({
      'version': 8,
      'name': 'Nuuk City Live ${palette.label} ${tone.label} raster',
      'sources': {
        'osm-raster': {
          'type': 'raster',
          'tiles': [NuukMap.rasterTileUrl],
          'tileSize': 256,
          'attribution': 'OpenStreetMap contributors',
        },
      },
      'layers': [
        {
          'id': 'background',
          'type': 'background',
          'paint': {'background-color': background},
        },
        {
          'id': 'osm-raster',
          'type': 'raster',
          'source': 'osm-raster',
          'paint': {'raster-opacity': opacity},
        },
      ],
    });
  }

  fm.TileBuilder get rasterTileBuilder {
    return (context, tileWidget, tile) {
      final tonedTile = tone == MapTone.dark
          ? fm.darkModeTileBuilder(context, tileWidget, tile)
          : tileWidget;
      final tint = palette == MapPalette.blueGreen
          ? const Color(0xFF0B7A75)
          : const Color(0xFFA2772B);

      return ColorFiltered(
        colorFilter: ColorFilter.mode(
          tint.withValues(alpha: tone == MapTone.dark ? 0.28 : 0.18),
          BlendMode.softLight,
        ),
        child: tonedTile,
      );
    };
  }
}

String _mapIconImageName(IconData icon, Color color, {required bool selected}) {
  final colorId = color.toString().replaceAll(RegExp('[^0-9A-Za-z]'), '');
  return 'ncl-${icon.codePoint}-$colorId-${selected ? 'selected' : 'normal'}';
}

Future<Uint8List> _markerImageBytes(
  IconData icon,
  Color color, {
  required bool selected,
}) async {
  final size = selected ? 72.0 : 58.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = Offset(size / 2, size / 2);
  final radius = selected ? 26.0 : 21.0;

  canvas.drawCircle(center, radius + 4, Paint()..color = Colors.white);
  canvas.drawCircle(center, radius, Paint()..color = color);
  canvas.drawCircle(
    center,
    radius + 7,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 5 : 3
      ..color = const Color(0xAA101820),
  );

  final textPainter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        color: Colors.white,
        fontFamily: icon.fontFamily,
        fontSize: selected ? 34 : 27,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  textPainter.paint(
    canvas,
    Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2),
  );

  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

String _normalizeLabel(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9æøå]+'), ' ').trim();
}
