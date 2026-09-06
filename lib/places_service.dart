import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';

class PlaceInfo {
  final String name;
  final String type;
  final LatLng location;

  const PlaceInfo({
    required this.name,
    required this.type,
    required this.location,
  });
}

class PlacesService {
  static const String _overpassUrl =
      'https://overpass-api.de/api/interpreter';

  String _filterForType(String type) {
    switch (type) {
      case 'مطعم':
        return '["amenity"="restaurant"]';
      case 'فندق':
        return '["tourism"="hotel"]';
      case 'مول':
        return '["shop"="mall"]';
      case 'محطة وقود':
        return '["amenity"="fuel"]';
      case 'صيدلية':
        return '["amenity"="pharmacy"]';
      default:
        return '';
    }
  }
}
