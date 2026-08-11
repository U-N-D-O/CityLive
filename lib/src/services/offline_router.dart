import 'dart:collection';
import 'dart:math';

import 'package:latlong2/latlong.dart';

class OfflineRoute {
  const OfflineRoute({
    required this.points,
    required this.distanceMeters,
    required this.segmentNames,
  });

  final List<LatLng> points;
  final double distanceMeters;
  final List<String> segmentNames;
}

class OfflineRouter {
  OfflineRouter._({
    required Map<String, _RouteNode> nodes,
    required Map<String, List<_RouteEdge>> edges,
  }) : _nodes = nodes,
       _edges = edges;

  final Map<String, _RouteNode> _nodes;
  final Map<String, List<_RouteEdge>> _edges;

  factory OfflineRouter.fromJson(Map<String, Object?> json) {
    final nodes = <String, _RouteNode>{};
    for (final rawNode in (json['nodes'] as List<Object?>)) {
      final node = rawNode as Map<String, Object?>;
      final id = node['id'] as String;
      nodes[id] = _RouteNode(
        id: id,
        coordinate: LatLng(
          (node['latitude'] as num).toDouble(),
          (node['longitude'] as num).toDouble(),
        ),
      );
    }

    final edges = <String, List<_RouteEdge>>{};
    for (final rawEdge in (json['edges'] as List<Object?>)) {
      final edge = rawEdge as Map<String, Object?>;
      final from = edge['from'] as String;
      edges
          .putIfAbsent(from, () => [])
          .add(
            _RouteEdge(
              to: edge['to'] as String,
              distance: (edge['distance'] as num).toDouble(),
              name: edge['name'] as String? ?? 'Road',
            ),
          );
    }

    return OfflineRouter._(nodes: nodes, edges: edges);
  }

  OfflineRoute? route({required LatLng from, required LatLng to}) {
    if (_nodes.isEmpty) {
      return null;
    }

    final startId = _nearestNodeId(from);
    final endId = _nearestNodeId(to);
    if (startId == null || endId == null) {
      return null;
    }

    final distances = <String, double>{startId: 0};
    final previous = <String, String>{};
    final previousRoad = <String, String>{};
    final queue = _MinQueue()..add(_QueueEntry(startId, 0));
    final visited = <String>{};

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (!visited.add(current.nodeId)) {
        continue;
      }

      if (current.nodeId == endId) {
        break;
      }

      for (final edge in _edges[current.nodeId] ?? const <_RouteEdge>[]) {
        final nextDistance = current.distance + edge.distance;
        if (nextDistance >= (distances[edge.to] ?? double.infinity)) {
          continue;
        }

        distances[edge.to] = nextDistance;
        previous[edge.to] = current.nodeId;
        previousRoad[edge.to] = edge.name;
        queue.add(_QueueEntry(edge.to, nextDistance));
      }
    }

    if (!distances.containsKey(endId)) {
      return null;
    }

    final nodePath = <String>[];
    var cursor = endId;
    while (cursor != startId) {
      nodePath.add(cursor);
      cursor = previous[cursor]!;
    }
    nodePath.add(startId);

    final orderedNodeIds = nodePath.reversed.toList(growable: false);
    final points = [
      from,
      for (final nodeId in orderedNodeIds) _nodes[nodeId]!.coordinate,
      to,
    ];
    final roads = <String>{};
    for (final nodeId in orderedNodeIds.skip(1)) {
      final roadName = previousRoad[nodeId];
      if (roadName != null) {
        roads.add(roadName);
      }
    }

    return OfflineRoute(
      points: points,
      distanceMeters: distances[endId]!,
      segmentNames: roads.toList(growable: false),
    );
  }

  String? _nearestNodeId(LatLng coordinate) {
    String? bestId;
    var bestDistance = double.infinity;

    for (final node in _nodes.values) {
      final distance = _distanceSquared(coordinate, node.coordinate);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestId = node.id;
      }
    }

    return bestId;
  }

  double _distanceSquared(LatLng left, LatLng right) {
    final latitudeDelta = left.latitude - right.latitude;
    final longitudeDelta =
        (left.longitude - right.longitude) * cos(left.latitude * pi / 180);
    return latitudeDelta * latitudeDelta + longitudeDelta * longitudeDelta;
  }
}

class _RouteNode {
  const _RouteNode({required this.id, required this.coordinate});

  final String id;
  final LatLng coordinate;
}

class _RouteEdge {
  const _RouteEdge({
    required this.to,
    required this.distance,
    required this.name,
  });

  final String to;
  final double distance;
  final String name;
}

class _QueueEntry {
  const _QueueEntry(this.nodeId, this.distance);

  final String nodeId;
  final double distance;
}

class _MinQueue {
  final _items = ListQueue<_QueueEntry>();

  bool get isNotEmpty => _items.isNotEmpty;

  void add(_QueueEntry entry) {
    if (_items.isEmpty) {
      _items.add(entry);
      return;
    }

    final ordered = _items.toList();
    var inserted = false;
    for (var index = 0; index < ordered.length; index++) {
      if (entry.distance < ordered[index].distance) {
        ordered.insert(index, entry);
        inserted = true;
        break;
      }
    }
    if (!inserted) {
      ordered.add(entry);
    }

    _items
      ..clear()
      ..addAll(ordered);
  }

  _QueueEntry removeFirst() => _items.removeFirst();
}
