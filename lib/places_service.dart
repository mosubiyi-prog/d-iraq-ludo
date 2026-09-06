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
      case 'مطاعم':
        return '["amenity"="restaurant"]';

      case 'فندق':
      case 'فنادق':
        return '["tourism"="hotel"]';

      case 'مول':
      case 'مولات':
        return '["shop"="mall"]';

      case 'محطة وقود':
      case 'محطات وقود':
        return '["amenity"="fuel"]';

      case 'صيدلية':
      case 'صيدليات':
        return '["amenity"="pharmacy"]';

      case 'موقف':
      case 'مواقف':
        return '["amenity"="parking"]';

      case 'حديقة':
      case 'حدائق':
        return '["leisure"="park"]';

      default:
        return '';
    }
  }

  Future<List<PlaceInfo>> getNearbyPlaces({
    required LatLng center,
    required String type,
    int radiusMeters = 3000,
  }) async {
    final filter = _filterForType(type);

    if (filter.isEmpty) {
      return [];
    }

    final latitude = center.latitude;
    final longitude = center.longitude;

    final query = '''
[out:json][timeout:25];
(
  node(around:$radiusMeters,$latitude,$longitude)$filter;
  way(around:$radiusMeters,$latitude,$longitude)$filter;
  relation(around:$radiusMeters,$latitude,$longitude)$filter;
);
out center tags;
''';

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    try {
      final request =
          await client.postUrl(Uri.parse(_overpassUrl));

      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded; charset=UTF-8',
      );

      request.write(
        'data=${Uri.encodeQueryComponent(query)}',
      );

      final response = await request.close();

      final body = await response
          .transform(utf8.decoder)
          .join();

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw HttpException(
          'Overpass error: ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        return [];
      }

      final elements = decoded['elements'];

      if (elements is! List) {
        return [];
      }

      final places = <PlaceInfo>[];

      for (final element in elements) {
        if (element is! Map) {
          continue;
        }

        final item =
            Map<String, dynamic>.from(element);

        final rawTags = item['tags'];

        final tags = rawTags is Map
            ? Map<String, dynamic>.from(rawTags)
            : <String, dynamic>{};

        final rawName =
            tags['name:ar'] ??
            tags['name'] ??
            type;

        final name = rawName.toString().trim();

        double? placeLatitude;
        double? placeLongitude;

        if (item['lat'] is num &&
            item['lon'] is num) {
          placeLatitude =
              (item['lat'] as num).toDouble();

          placeLongitude =
              (item['lon'] as num).toDouble();
        } else {
          final rawCenter = item['center'];

          if (rawCenter is Map) {
            final placeCenter =
                Map<String, dynamic>.from(rawCenter);

            if (placeCenter['lat'] is num &&
                placeCenter['lon'] is num) {
              placeLatitude =
                  (placeCenter['lat'] as num).toDouble();

              placeLongitude =
                  (placeCenter['lon'] as num).toDouble();
            }
          }
        }

        if (placeLatitude == null ||
            placeLongitude == null) {
          continue;
        }

        places.add(
          PlaceInfo(
            name: name.isEmpty ? type : name,
            type: type,
            location: LatLng(
              placeLatitude,
              placeLongitude,
            ),
          ),
        );
      }

      return places;
    } finally {
      client.close(force: true);
    }
  }
  }

