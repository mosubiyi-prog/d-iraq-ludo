import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class DedaAdminPlaceMapPage extends StatelessWidget {
  final bool isArabic;
  final double latitude;
  final double longitude;
  final String placeName;

  const DedaAdminPlaceMapPage({
    super.key,
    required this.isArabic,
    required this.latitude,
    required this.longitude,
    required this.placeName,
  });

  String t(String ar, String en) => isArabic ? ar : en;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(t('موقع الطلب - DEDA', 'Request location - DEDA')),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 17,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.diraq.ludo',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 64,
                      height: 64,
                      child: const Icon(
                        Icons.location_pin,
                        size: 58,
                        color: Color(0xFFB3261E),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              color: const Color(0xFFF8FAF2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    placeName.trim().isEmpty
                        ? t('موقع المكان المطلوب', 'Requested place location')
                        : placeName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
