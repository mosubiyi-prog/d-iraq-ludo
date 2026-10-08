import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

// 100312: optional, asynchronous OSM highway classification. Never blocks GPS.
// Unknown road class keeps conservative 500m voice / 300m map warning.
class DedaRoadClassLookup {
  static const _residential = <String>{
    'residential', 'living_street', 'service', 'pedestrian', 'footway', 'path',
  };
  static const _external = <String>{
    'motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary',
    'primary_link', 'secondary', 'secondary_link', 'tertiary',
    'tertiary_link', 'unclassified',
  };

  static double _distance(LatLng point, LatLng a, LatLng b) {
    final cosLat = math.cos(point.latitude * math.pi / 180);
    final ax = (a.longitude - point.longitude) * cosLat * 111195;
    final ay = (a.latitude - point.latitude) * 111195;
    final bx = (b.longitude - point.longitude) * cosLat * 111195;
    final by = (b.latitude - point.latitude) * 111195;
    final dx = bx - ax;
    final dy = by - ay;
    final length = dx * dx + dy * dy;
    final f = length <= 0
        ? 0.0
        : (-(ax * dx + ay * dy) / length).clamp(0.0, 1.0).toDouble();
    return math.sqrt(math.pow(ax + f * dx, 2) + math.pow(ay + f * dy, 2));
  }

  static bool _parallel(LatLng a, LatLng b, double? heading) {
    if (heading == null) return true;
    final east = (b.longitude - a.longitude) *
        math.cos((a.latitude + b.latitude) * math.pi / 360);
    final north = b.latitude - a.latitude;
    if (east.abs() + north.abs() < 0.00000001) return false;
    final bearing = (math.atan2(east, north) * 180 / math.pi + 360) % 360;
    final delta = ((bearing - heading + 540) % 360 - 180).abs();
    return math.min(delta, 180 - delta) <= 40;
  }

  static Future<Map<String, String>> lookup(
    List<({String id, LatLng location, double? routeHeading})> hazards,
  ) async {
    if (hazards.isEmpty) return <String, String>{};
    final candidates = hazards.take(8).toList(growable: false);
    final segments = candidates.map((hazard) {
      final latitude = hazard.location.latitude.toStringAsFixed(6);
      final longitude = hazard.location.longitude.toStringAsFixed(6);
      return 'way(around:45,$latitude,$longitude)["highway"];';
    }).join();
    final query = '[out:json][timeout:8];($segments);out geom;';
    Map<String, dynamic>? decoded;
    for (final endpoint in <String>[
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
    ]) {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.postUrl(Uri.parse(endpoint))
            .timeout(const Duration(seconds: 6));
        request.headers.set(HttpHeaders.contentTypeHeader,
            'application/x-www-form-urlencoded');
        request.headers.set(HttpHeaders.userAgentHeader, 'DEDA-Iraq/1.1');
        request.write('data=' + Uri.encodeQueryComponent(query));
        final response = await request.close()
            .timeout(const Duration(seconds: 9));
        if (response.statusCode != HttpStatus.ok) continue;
        final body = await utf8.decoder.bind(response).join()
            .timeout(const Duration(seconds: 9));
        final value = jsonDecode(body);
        if (value is Map) {
          decoded = Map<String, dynamic>.from(value);
          break;
        }
      } catch (_) {
        // Never let optional OSM lookups interfere with driving or navigation.
      } finally {
        client.close(force: true);
      }
    }
    if (decoded == null || decoded['elements'] is! List) {
      return <String, String>{};
    }

    final found = <String, String>{};
    for (final hazard in candidates) {
      var bestMeters = double.infinity;
      String? bestClass;
      for (final raw in decoded['elements'] as List) {
        if (raw is! Map || raw['tags'] is! Map ||
            raw['geometry'] is! List) continue;
        final highway = ((raw['tags'] as Map)['highway'] ?? '').toString();
        if (!_residential.contains(highway) && !_external.contains(highway)) {
          continue;
        }
        final nodes = raw['geometry'] as List;
        for (var i = 0; i + 1 < nodes.length; i++) {
          final first = nodes[i];
          final second = nodes[i + 1];
          if (first is! Map || second is! Map ||
              first['lat'] is! num || first['lon'] is! num ||
              second['lat'] is! num || second['lon'] is! num) continue;
          final a = LatLng((first['lat'] as num).toDouble(),
              (first['lon'] as num).toDouble());
          final b = LatLng((second['lat'] as num).toDouble(),
              (second['lon'] as num).toDouble());
          if (!_parallel(a, b, hazard.routeHeading)) continue;
          final meters = _distance(hazard.location, a, b);
          // Select the closest OSM road ALIGNED with the actual route, not
          // the adjacent residential side road at an intersection.
          if (meters < 28 && meters < bestMeters) {
            bestMeters = meters;
            bestClass = _residential.contains(highway)
                ? 'residential' : 'external';
          }
        }
      }
      if (bestClass != null) found[hazard.id] = bestClass;
    }
    return found;
  }
}
