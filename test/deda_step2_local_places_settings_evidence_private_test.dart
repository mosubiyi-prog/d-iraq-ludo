import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_local_places_settings_evidence.dart';

class FakeLocal implements DedaStep2LegacyPlacesSettingsIo {
  FakeLocal(this.data, {this.afterRead});
  final Map<String,Object?> data;
  final void Function()? afterRead;
  int reads=0, writes=0;
  @override
  Future<Map<String,Object?>> readExact(List<String> keys) async {
    reads++;
    afterRead?.call();
    return {for (final key in keys) key:data[key]};
  }
}

const account='07712345678',original='@DEDA-ABC123';
DedaStep2LocalPlacesSettingsReader reader(FakeLocal io) =>
  DedaStep2LocalPlacesSettingsReader(io);

void main() {
  test('reads exact old phone favorites, recents and preferences without writes', () async {
    final io=FakeLocal({
      'deda_favorites_v1':['{"name":"saved 1"}'],
      'deda_recent_v1':['{"name":"recent 1"}'],
      'deda_personal_places_v1':'[{"id":"old-place","name":"old"}]',
      'deda_language_v1':'ar',
      'deda_voice_enabled_v1':true,
      'deda_speech_rate_v1':0.45,
      'deda_default_travel_mode_v1':'car',
      'deda_default_map_style_v1':'normal',
      'deda_profile_frame_v1_$account':1,
    });
    final e=await reader(io).inspectOriginalPhone(
      accountKey:account,originalId:original,isCurrent:()=>true);
    expect(e.hasAnySource,true);
    expect(e.values['deda_personal_places_v1'],
      '[{"id":"old-place","name":"old"}]');
    expect(e.status['deda_favorites_v1'],
      DedaStep2LocalSourceStatus.capturedUntrusted);
    expect(e.status['deda_profile_frame_v1_$account'],
      DedaStep2LocalSourceStatus.capturedUntrusted);
    expect(e.fullAccountRestored,false);
    expect(e.canImportGlobalPreferencesToAnotherPhone,false);
    expect(e.canCreditPointsOrDiamonds,false);
    expect(io.writes,0);
    expect(io.reads,1);
  });

  test('missing local favorites is UNKNOWN and never empty restore', () async {
    final e=await reader(FakeLocal({})).inspectOriginalPhone(
      accountKey:account,originalId:original,isCurrent:()=>true);
    expect(e.values['deda_favorites_v1'],isNull);
    expect(e.status['deda_favorites_v1'],
      DedaStep2LocalSourceStatus.missingUnknown);
  });

  test('corrupt or unexpectedly typed legacy data is preserved for review', () async {
    final e=await reader(FakeLocal({
      'deda_favorites_v1':['bad-json'],
      'deda_personal_places_v1':'[not-json',
      'deda_voice_enabled_v1':'true',
      'deda_profile_frame_v1_$account':17,
    })).inspectOriginalPhone(accountKey:account,originalId:original,
        isCurrent:()=>true);
    expect(e.status['deda_favorites_v1'],
      DedaStep2LocalSourceStatus.malformedUntrusted);
    expect(e.status['deda_personal_places_v1'],
      DedaStep2LocalSourceStatus.malformedUntrusted);
    expect(e.values['deda_personal_places_v1'],'[not-json');
    expect(e.canImportGlobalPreferencesToAnotherPhone,false);
  });

  test('account intent changed after async read invalidates all evidence', () async {
    var current=true;
    final io=FakeLocal({},afterRead:(){current=false;});
    await expectLater(reader(io).inspectOriginalPhone(
      accountKey:account,originalId:original,isCurrent:()=>current),
      throwsStateError);
    expect(io.writes,0);
  });

  test('invalid phone or alias blocks read before touching local prefs', () async {
    final io=FakeLocal({});
    for(final data in [
      (phone:'other',id:original),
      (phone:account,id:'@DEDA-SPECIAL-001'),
    ]) {
      await expectLater(reader(io).inspectOriginalPhone(
        accountKey:data.phone,originalId:data.id,isCurrent:()=>true),
        throwsStateError);
    }
    expect(io.reads,0);
  });

  test('returned collections are immutable and cannot alter evidence', () async {
    final old=['{"name":"one"}'];
    final e=await reader(FakeLocal({'deda_recent_v1':old}))
      .inspectOriginalPhone(accountKey:account,originalId:original,
        isCurrent:()=>true);
    old.add('{"name":"two"}');
    expect((e.values['deda_recent_v1'] as List).length,1);
    expect(() => e.values['deda_recent_v1']=null,throwsUnsupportedError);
  });
}
