import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Snapshot of exact 100436/100340 on-device keys: read-only only.
enum DedaStep2LocalSourceStatus {
  missingUnknown,
  capturedUntrusted,
  malformedUntrusted,
}

class DedaStep2LocalPlacesSettingsEvidence {
  const DedaStep2LocalPlacesSettingsEvidence({
    required this.accountKey,
    required this.originalId,
    required this.values,
    required this.status,
  });

  final String accountKey, originalId;
  /// Raw original bytes/types; no normalization, empty fallback or migration.
  final Map<String,Object?> values;
  final Map<String,DedaStep2LocalSourceStatus> status;

  bool get hasAnySource => values.values.any((value) => value != null);
  bool get fullAccountRestored => false;
  bool get canCreditPointsOrDiamonds => false;
  /// Most place/settings preferences are DEVICE-GLOBAL, not account scoped.
  /// Old-phone proof + immutable account backup + safe merge are still needed.
  bool get canImportGlobalPreferencesToAnotherPhone => false;
  bool get canEraseOriginalPhone => false;
}

abstract class DedaStep2LegacyPlacesSettingsIo {
  Future<Map<String,Object?>> readExact(List<String> keys);
}

class DedaStep2PreferencesPlacesSettingsIo
    implements DedaStep2LegacyPlacesSettingsIo {
  const DedaStep2PreferencesPlacesSettingsIo();

  @override
  Future<Map<String,Object?>> readExact(List<String> keys) async {
    final preferences = await SharedPreferences.getInstance();
    return {
      for (final key in keys)
        key: preferences.get(key), // Preserve true type, never default to [].
    };
  }
}

/// Does NOT import main.dart or call DedaPlacesStore. Its legacy readers
/// silently skip invalid items; a recovery audit must preserve those bytes
/// and flag the loss, not infer an empty inventory.
class DedaStep2LocalPlacesSettingsReader {
  const DedaStep2LocalPlacesSettingsReader(this.io);
  final DedaStep2LegacyPlacesSettingsIo io;

  static const globalPlacesAndSettings = <String>[
    'deda_favorites_v1',
    'deda_recent_v1',
    'deda_personal_places_v1',
    'deda_language_v1',
    'deda_voice_enabled_v1',
    'deda_speech_rate_v1',
    'deda_default_travel_mode_v1',
    'deda_default_map_style_v1',
  ];

  static String profileFreeFrameKey(String accountKey) =>
      'deda_profile_frame_v1_$accountKey';

  static DedaStep2LocalSourceStatus _inspect(String key, Object? value) {
    if (value == null) return DedaStep2LocalSourceStatus.missingUnknown;
    bool valid = false;
    try {
      if (key == 'deda_favorites_v1' || key == 'deda_recent_v1') {
        final limit = key == 'deda_favorites_v1' ? 100 : 30;
        valid = value is List<String> && value.length <= limit &&
            value.every((raw) {
              if (raw.length > 12000) return false;
              final decoded = jsonDecode(raw);
              return decoded is Map;
            });
      } else if (key == 'deda_personal_places_v1') {
        if (value is String && value.length <= 500000) {
          final decoded = jsonDecode(value);
          valid = decoded is List && decoded.length <= 200 &&
              decoded.every((item) => item is Map);
        }
      } else if (key == 'deda_voice_enabled_v1') {
        valid = value is bool;
      } else if (key == 'deda_speech_rate_v1') {
        valid = value is double && value.isFinite && value >= 0.1 &&
            value <= 2.0;
      } else if (key.startsWith('deda_profile_frame_v1_')) {
        valid = value is int && value >= 0 && value <= 2;
      } else {
        valid = value is String && value.trim().isNotEmpty &&
            value.length <= 100;
      }
    } catch (_) {
      valid = false;
    }
    return valid ? DedaStep2LocalSourceStatus.capturedUntrusted
        : DedaStep2LocalSourceStatus.malformedUntrusted;
  }

  Future<DedaStep2LocalPlacesSettingsEvidence> inspectOriginalPhone({
    required String accountKey,
    required String originalId,
    required bool Function() isCurrent,
  }) async {
    if (!RegExp(r'^\d{10,16}$').hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
      throw StateError('local-places-invalid-account-scope');
    }
    void check() {
      if (!isCurrent()) {
        throw StateError('local-places-original-intent-changed');
      }
    }
    check();
    final keys = List<String>.unmodifiable([
      ...globalPlacesAndSettings,
      profileFreeFrameKey(accountKey),
    ]);
    final response = await io.readExact(keys);
    check();
    if (response.length != keys.length ||
        keys.any((key) => !response.containsKey(key))) {
      throw StateError('local-places-incomplete-read');
    }
    final raw = <String,Object?>{};
    for (final key in keys) {
      final value = response[key];
      // Never leak a mutable list supplied by an external mock/store.
      raw[key] = value is List ? List<Object?>.unmodifiable(value) : value;
    }
    final status = <String,DedaStep2LocalSourceStatus>{
      for (final key in keys) key: _inspect(key, raw[key]),
    };
    check();
    return DedaStep2LocalPlacesSettingsEvidence(
      accountKey:accountKey,originalId:originalId,
      values:Map.unmodifiable(raw),status:Map.unmodifiable(status));
  }
}
