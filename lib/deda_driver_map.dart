import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// DEDA 100308 — isolated true-pitch Driver renderer.
///
/// This widget owns ONLY the visual renderer used while Driver View is active.
/// GPS, routing, rerouting, hazards, voice and task logic stay in main.dart.
///
/// Visual reference locked for this renderer:
/// - real camera tilt: 52° (accepted range 45–55°)
/// - horizon/sky: 20% portrait, 16% landscape, never painted over the map
/// - route/road labels are rendered on the pitched map surface
/// - live point is lower on screen because camera target is supplied ahead
/// - no Matrix4 fake perspective is used here.
class DedaDriverMap extends StatefulWidget {
  const DedaDriverMap({
    super.key,
    required this.current,
    required this.cameraTarget,
    required this.destination,
    required this.routePoints,
    required this.headingDegrees,
    required this.zoom,
    required this.followEnabled,
    required this.onMapGesture,
  });

  final ll.LatLng current;
  final ll.LatLng cameraTarget;
  final ll.LatLng destination;
  final List<ll.LatLng> routePoints;
  final double headingDegrees;
  final double zoom;
  final bool followEnabled;
  final VoidCallback onMapGesture;

  @override
  State<DedaDriverMap> createState() => _DedaDriverMapState();
}

class _DedaDriverMapState extends State<DedaDriverMap> {
  ml.MaplibreMapController? _controller;
  ml.Line? _routeShadow;
  ml.Line? _routeCore;
  bool _styleReady = false;
  int _routeSignature = 0;

  static const double _driverTilt = 52.0;

  static const String _osmStyle = '''
{
  "version": 8,
  "name": "DEDA Driver OSM",
  "sources": {
    "osm": {
      "type": "raster",
      "tiles": ["https://tile.openstreetmap.org/{z}/{x}/{y}.png"],
      "tileSize": 256,
      "minzoom": 0,
      "maxzoom": 19,
      "attribution": "© OpenStreetMap contributors"
    }
  },
  "layers": [
    {
      "id": "osm",
      "type": "raster",
      "source": "osm",
      "minzoom": 0,
      "maxzoom": 22
    }
  ]
}
''';

  ml.LatLng _ml(ll.LatLng p) => ml.LatLng(p.latitude, p.longitude);

  double _meters(ll.LatLng a, ll.LatLng b) {
    const radius = 6371000.0;
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dp = (b.latitude - a.latitude) * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) *
            math.cos(p2) *
            math.sin(dl / 2) *
            math.sin(dl / 2);
    return radius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  List<ll.LatLng> _visibleRoute() {
    final points = widget.routePoints;
    if (points.length < 2) {
      return <ll.LatLng>[widget.current, widget.destination];
    }

    var nearestIndex = 0;
    var nearestMeters = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = _meters(widget.current, points[i]);
      if (d < nearestMeters) {
        nearestMeters = d;
        nearestIndex = i;
      }
    }

    final destinationNearLast =
        _meters(points.last, widget.destination) <=
        _meters(points.first, widget.destination);

    final visible = <ll.LatLng>[widget.current];
    if (destinationNearLast) {
      final start = math.max(0, nearestIndex - 1);
      visible.addAll(points.skip(start));
    } else {
      final start = math.min(points.length - 1, nearestIndex + 1);
      for (var i = start; i >= 0; i--) {
        visible.add(points[i]);
      }
    }

    if (_meters(visible.last, widget.destination) > 8) {
      visible.add(widget.destination);
    }
    return visible;
  }

  int _signature(List<ll.LatLng> points) {
    if (points.isEmpty) return 0;
    final first = points.first;
    final last = points.last;
    return Object.hash(
      points.length,
      first.latitude.toStringAsFixed(5),
      first.longitude.toStringAsFixed(5),
      last.latitude.toStringAsFixed(5),
      last.longitude.toStringAsFixed(5),
    );
  }

  ml.CameraPosition _cameraPosition() {
    return ml.CameraPosition(
      target: _ml(widget.cameraTarget),
      zoom: widget.zoom,
      tilt: _driverTilt,
      bearing: (widget.headingDegrees + 360) % 360,
    );
  }

  Future<void> _moveCamera() async {
    final controller = _controller;
    if (controller == null || !widget.followEnabled) return;
    try {
      await controller.animateCamera(
        ml.CameraUpdate.newCameraPosition(_cameraPosition()),
      );
    } catch (_) {
      // Renderer failures must never affect navigation logic.
    }
  }

  Future<void> _syncRoute({bool force = false}) async {
    final controller = _controller;
    if (!_styleReady || controller == null) return;

    final visible = _visibleRoute();
    final sig = _signature(visible);
    if (!force && sig == _routeSignature) return;
    _routeSignature = sig;

    try {
      if (_routeCore != null) {
        await controller.removeLine(_routeCore!);
        _routeCore = null;
      }
      if (_routeShadow != null) {
        await controller.removeLine(_routeShadow!);
        _routeShadow = null;
      }

      final geometry = visible.map(_ml).toList(growable: false);
      if (geometry.length < 2) return;

      _routeShadow = await controller.addLine(
        ml.LineOptions(
          geometry: geometry,
          lineColor: '#073C20',
          lineWidth: 13.0,
          lineOpacity: 0.96,
        ),
      );
      _routeCore = await controller.addLine(
        ml.LineOptions(
          geometry: geometry,
          lineColor: '#22D866',
          lineWidth: 8.0,
          lineOpacity: 1.0,
        ),
      );
    } catch (_) {
      // Keep the map visible even if an annotation update fails.
    }
  }

  @override
  void didUpdateWidget(covariant DedaDriverMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    final cameraChanged =
        oldWidget.cameraTarget.latitude != widget.cameraTarget.latitude ||
        oldWidget.cameraTarget.longitude != widget.cameraTarget.longitude ||
        (oldWidget.headingDegrees - widget.headingDegrees).abs() > 0.2 ||
        (oldWidget.zoom - widget.zoom).abs() > 0.01 ||
        oldWidget.followEnabled != widget.followEnabled;

    final routeChanged =
        oldWidget.routePoints.length != widget.routePoints.length ||
        oldWidget.destination != widget.destination;

    if (cameraChanged) {
      unawaited(_moveCamera());
    }
    if (routeChanged ||
        _meters(oldWidget.current, widget.current) >= 18) {
      unawaited(_syncRoute());
    }
  }

  Future<void> _onMapCreated(ml.MaplibreMapController controller) async {
    _controller = controller;
    await _moveCamera();
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = true;
    await _syncRoute(force: true);
    await _moveCamera();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final skyFraction = landscape ? 0.16 : 0.20;

    return LayoutBuilder(
      builder: (context, constraints) {
        final skyHeight = constraints.maxHeight * skyFraction;
        return Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF8FD2FF),
                    Color(0xFFCBEAFF),
                    Color(0xFFF7FBFF),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: skyHeight,
              bottom: 0,
              child: ClipRect(
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (_) => widget.onMapGesture(),
                  child: ml.MaplibreMap(
                    styleString: _osmStyle,
                    initialCameraPosition: _cameraPosition(),
                    onMapCreated: _onMapCreated,
                    onStyleLoadedCallback: _onStyleLoaded,
                    myLocationEnabled: false,
                    compassEnabled: false,
                  ),
                ),
              ),
            ),
            Positioned(
              top: math.max(0, skyHeight - 2),
              left: 0,
              right: 0,
              height: 4,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withOpacity(0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              right: 6,
              bottom: 4,
              child: IgnorePointer(
                child: Text(
                  '© OpenStreetMap',
                  style: TextStyle(
                    fontSize: 9,
                    color: Color(0xFF4D5A61),
                    backgroundColor: Color(0xAAFFFFFF),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
