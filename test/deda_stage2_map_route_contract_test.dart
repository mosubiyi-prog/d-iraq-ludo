import 'package:d_iraq_ludo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('four original travel modes remain available', () {
    expect(DedaTravelMode.values.toSet(), {
      DedaTravelMode.car, DedaTravelMode.motorcycle,
      DedaTravelMode.truck, DedaTravelMode.walking,
    });
  });
  test('all ten original hazard types preserve labels and icons', () {
    expect(DedaRoadHazard.reportTypes.toSet(), {
      'bump', 'roadworks', 'maintenance', 'detour', 'speed_camera',
      'checkpoint', 'accident', 'congestion', 'road_object', 'flooded',
    });
    for (final type in DedaRoadHazard.reportTypes) {
      expect(DedaRoadHazard.labelForType(type), isNotEmpty);
      expect(DedaRoadHazard.iconForType(type), isNot(Icons.report_problem_outlined));
    }
  });
  test('hazard payload retains document ID, exact position, votes and expiry', () {
    final expired = DedaRoadHazard.fromMap({
      'id': 'original-hazard', 'type': 'bump',
      'latitude': 33.25, 'longitude': 44.75, 'confirmations': 3,
      'resolvedReports': 2, 'expiresAtMillis': 1,
    });
    expect(expired.id, 'original-hazard');
    expect(expired.location.latitude, 33.25);
    expect(expired.location.longitude, 44.75);
    expect(expired.confirmations, 3);
    expect(expired.resolvedReports, 2);
    expect(expired.isExpired, true);
    expect(DedaRoadHazard.fromMap({'expiresAtMillis': 0}).isExpired, false);
  });
  test('route result retains geometry, distance, duration and maneuver', () {
    const step = DedaRouteStep(instruction: 'Turn', distanceMeters: 350,
      maneuverType: 'turn', maneuverModifier: 'left',
      maneuverPoint: LatLng(33.3, 44.4));
    const route = DedaRouteResult(points: [LatLng(33.3, 44.4), LatLng(33.4, 44.5)],
      distanceMeters: 1200, durationSeconds: 180, steps: [step]);
    expect(route.points.length, 2);
    expect(route.distanceMeters, 1200);
    expect(route.durationSeconds, 180);
    expect(route.steps.single.maneuverModifier, 'left');
    expect(route.steps.single.maneuverPoint!.latitude, 33.3);
    expect(route.isDirectFallback, false);
  });
}
