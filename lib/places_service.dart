import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:latlong2/latlong.dart';

class PlaceInfo {
  final String name;
  final String type;
  final LatLng location;
  final String? address;
  final String? phone;
  final String? website;
  final String? openingHours;

  const PlaceInfo({
    required this.name,
    required this.type,
    required this.location,
    this.address,
    this.phone,
    this.website,
    this.openingHours,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'type': type,
        'lat': location.latitude,
        'lon': location.longitude,
        'address': address,
        'phone': phone,
        'website': website,
        'openingHours': openingHours,
      };

  factory PlaceInfo.fromJson(Map<String, dynamic> json) {
    return PlaceInfo(
      name: (json['name'] ?? 'مكان').toString(),
      type: (json['type'] ?? 'مكان').toString(),
      location: LatLng(
        (json['lat'] as num).toDouble(),
        (json['lon'] as num).toDouble(),
      ),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      website: json['website']?.toString(),
      openingHours: json['openingHours']?.toString(),
    );
  }
}

class PlacesService {
  static const List<String> _overpassUrls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  static const Duration _requestTimeout = Duration(seconds: 14);

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
    if (filter.isEmpty) return [];

    final query = '''
[out:json][timeout:14];
nwr(around:$radiusMeters,${center.latitude},${center.longitude})$filter;
out center tags;
''';

    return _requestPlaces(query: query, fallbackType: type);
  }

  Future<List<PlaceInfo>> searchPlacesByName({
    required LatLng center,
    required String queryText,
    int radiusMeters = 25000,
  }) async {
    final text = queryText.trim();
    if (text.length < 2) return [];

    final escaped = _escapeOverpassRegex(text);
    final query = '''
[out:json][timeout:14];
(
  nwr(around:$radiusMeters,${center.latitude},${center.longitude})["name"~"$escaped",i];
  nwr(around:$radiusMeters,${center.latitude},${center.longitude})["name:ar"~"$escaped",i];
);
out center tags;
''';

    final results = await _requestPlaces(
      query: query,
      fallbackType: 'مكان',
    );

    final seen = <String>{};
    final unique = <PlaceInfo>[];
    for (final place in results) {
      final key = '${place.name.toLowerCase()}|'
          '${place.location.latitude.toStringAsFixed(5)}|'
          '${place.location.longitude.toStringAsFixed(5)}';
      if (seen.add(key)) unique.add(place);
    }
    return unique;
  }

  String _escapeOverpassRegex(String value) {
    final escaped = value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"');
    return escaped.replaceAllMapped(
      RegExp(r'([.^$*+?()\[\]{}|])'),
      (match) => '\\${match.group(0)}',
    );
  }

  Future<List<PlaceInfo>> _requestPlaces({
    required String query,
    required String fallbackType,
  }) async {
    Object? lastError;

    for (final endpoint in _overpassUrls) {
      try {
        return await _fetchFromEndpoint(
          endpoint: endpoint,
          query: query,
          fallbackType: fallbackType,
        ).timeout(_requestTimeout);
      } on TimeoutException {
        lastError = HttpException(
          'Overpass timeout after ${_requestTimeout.inSeconds}s ($endpoint)',
        );
      } on SocketException catch (error) {
        lastError = SocketException(
          '${error.message} ($endpoint)',
          osError: error.osError,
          address: error.address,
          port: error.port,
        );
      } on HttpException catch (error) {
        lastError = error;
      } on FormatException catch (error) {
        lastError = error;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError != null) throw lastError;
    return [];
  }

  Future<List<PlaceInfo>> _fetchFromEndpoint({
    required String endpoint,
    required String query,
    required String fallbackType,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);

    try {
      final uri = Uri.parse(endpoint).replace(
        queryParameters: <String, String>{'data': query},
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'DEDA/1.0 (Android)');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Overpass error: ${response.statusCode} ($endpoint)',
        );
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Overpass response is not a JSON object');
      }

      final elements = decoded['elements'];
      if (elements is! List) return [];

      final places = <PlaceInfo>[];
      for (final element in elements) {
        if (element is! Map) continue;
        final item = Map<String, dynamic>.from(element);
        final rawTags = item['tags'];
        final tags = rawTags is Map
            ? Map<String, dynamic>.from(rawTags)
            : <String, dynamic>{};

        final rawName = tags['name:ar'] ?? tags['name'] ?? fallbackType;
        final name = rawName.toString().trim();

        double? latitude;
        double? longitude;
        if (item['lat'] is num && item['lon'] is num) {
          latitude = (item['lat'] as num).toDouble();
          longitude = (item['lon'] as num).toDouble();
        } else if (item['center'] is Map) {
          final center = Map<String, dynamic>.from(item['center'] as Map);
          if (center['lat'] is num && center['lon'] is num) {
            latitude = (center['lat'] as num).toDouble();
            longitude = (center['lon'] as num).toDouble();
          }
        }
        if (latitude == null || longitude == null) continue;

        places.add(
          PlaceInfo(
            name: name.isEmpty ? fallbackType : name,
            type: _typeFromTags(tags, fallbackType),
            location: LatLng(latitude, longitude),
            address: _addressFromTags(tags),
            phone: _firstText(tags, const ['contact:phone', 'phone']),
            website: _firstText(tags, const ['contact:website', 'website']),
            openingHours: _firstText(tags, const ['opening_hours']),
          ),
        );
      }
      return places;
    } finally {
      client.close(force: true);
    }
  }

  String _typeFromTags(Map<String, dynamic> tags, String fallback) {
    final amenity = tags['amenity']?.toString();
    final tourism = tags['tourism']?.toString();
    final shop = tags['shop']?.toString();
    final leisure = tags['leisure']?.toString();

    switch (amenity) {
      case 'restaurant':
        return 'مطعم';
      case 'pharmacy':
        return 'صيدلية';
      case 'fuel':
        return 'محطة وقود';
      case 'parking':
        return 'موقف';
      case 'cafe':
        return 'مقهى';
      case 'hospital':
        return 'مستشفى';
      case 'school':
        return 'مدرسة';
      case 'bank':
        return 'مصرف';
    }
    if (tourism == 'hotel') return 'فندق';
    if (shop == 'mall') return 'مول';
    if (leisure == 'park') return 'حديقة';
    return fallback.isEmpty ? 'مكان' : fallback;
  }

  String? _addressFromTags(Map<String, dynamic> tags) {
    final direct = _firstText(tags, const ['addr:full']);
    if (direct != null) return direct;

    final parts = <String>[
      if ((tags['addr:street'] ?? '').toString().trim().isNotEmpty)
        tags['addr:street'].toString().trim(),
      if ((tags['addr:housenumber'] ?? '').toString().trim().isNotEmpty)
        tags['addr:housenumber'].toString().trim(),
      if ((tags['addr:city'] ?? '').toString().trim().isNotEmpty)
        tags['addr:city'].toString().trim(),
    ];
    return parts.isEmpty ? null : parts.join('، ');
  }

  String? _firstText(Map<String, dynamic> tags, List<String> keys) {
    for (final key in keys) {
      final value = tags[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
