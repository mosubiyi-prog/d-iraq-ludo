"""Map part 1/5: read-only parity gate on the actual full assembled app.

The immutable 100380 archive is hash-verified by the existing profile helper.
Do not overwrite any map code, change providers, touch Firebase or enable flags.
A later part must extend the gate, not silently remove a protected feature.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('home_binder', ROOT/'tools/app_stability/app_package/bind_stage2_home_2026_11_24.py')
home = importlib.util.module_from_spec(spec)
spec.loader.exec_module(home)

# Keep every provider/caching/attribution function byte-for-byte at token level.
FOUNDATION = (
    'enum DedaMapStyle ', 'enum DedaTravelMode ',
    'TileLayer dedaFastTileLayer(', 'List<Widget> dedaBaseMapLayers(',
    'String dedaMapAttribution(', 'List<Widget> dedaNavigationMapLayers(',
    'String dedaNavigationMapAttribution(',
)
# All five parts have a named inventory before any later code changes.
INVENTORY = {
    '1': ('MapReadyPage', '_MapReadyPageState', 'DedaFullScreenMapPage',
          '_DedaFullScreenMapPageState'),
    '2': ('NearbyPlacesPage', '_NearbyPlacesPageState', 'DedaPlaceSearchPage',
          '_DedaPlaceSearchPageState', 'DedaMapPlaceMarker', 'PlaceDetailsPage',
          '_PlaceDetailsPageState'),
    '3': ('OwnerPlacePage', '_OwnerPlacePageState', 'PersonalPlaceEditorPage',
          '_PersonalPlaceEditorPageState', 'PersonalPlacesPage',
          '_PersonalPlacesPageState', 'DedaPersonalPlace', 'DedaPlacesStore',
          'DedaRegisteredPlacesStore', 'SavedPlacesPage', '_SavedPlacesPageState',
          'DedaMakaniPage', '_DedaMakaniPageState'),
    '4': ('DedaShareLocationPage', '_DedaShareLocationPageState',
          'DedaReceivedLocationsPage', '_DedaReceivedLocationsPageState'),
    '5': ('DedaRoutePage', '_DedaRoutePageState', 'DedaRouteService',
          'DedaRouteStep', 'DedaRouteResult', 'DedaRoadHazard', 'DedaLongTripProgress'),
}

def require(body, markers, label):
    for marker in markers:
        if marker not in body:
            raise ValueError('MAP_FOUNDATION_MISSING:' + label + ':' + marker)

def member(source, marker):
    a,z = home.span(source, marker)
    return source[a:z]

def tokens(source):
    return [value for value,_,_ in home.tokens(source)]

def digest(source):
    return hashlib.sha256(source.encode('utf-8')).hexdigest()

def visible_literals(source):
    # Preserve every literal Arabic/English UI label, color and icon on core
    # maps. Existing section guards are allowed to insert new guard messages,
    # but not remove the original map labels or reorder them.
    return [x for x in tokens(source) if
            (x.startswith(("'", '"')) and
             (re.search(r'[\u0600-\u06ff]', x) or 'http' in x))
            or x.startswith('0x')]

def ordered_subset(original, current, label):
    offset = 0
    for item in original:
        try:
            offset = current.index(item, offset) + 1
        except ValueError:
            raise ValueError('MAP_FOUNDATION_PARITY:' + label + ':' + item) from None

def verify(main, reference, require_bound=True):
    for marker in FOUNDATION:
        if tokens(member(main, marker)) != tokens(member(reference, marker)):
            raise ValueError('MAP_FOUNDATION_PROVIDER_OR_STYLE_DRIFT:' + marker)
    # This is an inventory, not a claim that all five parts are completed.
    inventory = {}
    for part, names in INVENTORY.items():
        inventory[part] = {}
        for name in names:
            old = member(reference, 'class ' + name + ' ')
            new = member(main, 'class ' + name + ' ')
            inventory[part][name] = {
                'reference_sha256': digest(old), 'assembled_sha256': digest(new)}
    for name, widget in (('_MapReadyPageState', 'MapReadyPage'),
                         ('_DedaFullScreenMapPageState', 'DedaFullScreenMapPage')):
        old = member(reference, 'class ' + name + ' ')
        new = member(main, 'class ' + name + ' ')
        if home.visual_signature(old) != home.visual_signature(new):
            raise ValueError('MAP_FOUNDATION_VISUAL_DRIFT:' + name)
        ordered_subset(visible_literals(old), visible_literals(new), name)
        for needle in ('FlutterMap(', 'MapOptions(', 'dedaBaseMapLayers(mapStyle)',
                       'RichAttributionWidget(', 'dedaMapAttribution(mapStyle)',
                       'DedaMapStyle.values', 'InteractiveFlag.all',
                       'showAvailableOnly', 'MarkerLayer('):
            # Some controls differ by original map screen; require exactly
            # those actually present in the protected reference.
            if needle in old and needle not in new:
                raise ValueError('MAP_FOUNDATION_CONTROL_DRIFT:' + name + ':' + needle)
        if require_bound:
            require(new, ('DedaSectionState<' + widget + '>', 'dedaSectionExpiredView()'), name)
    core = member(main, 'class _MapReadyPageState ')
    require(core, ('Geolocator.isLocationServiceEnabled()', 'Geolocator.checkPermission()',
                   'Geolocator.requestPermission()', 'LocationPermission.deniedForever',
                   'Geolocator.getCurrentPosition(', 'LocationAccuracy.high',
                   'Geolocator.openAppSettings()', 'initialZoom: 11.8',
                   'InteractiveFlag.all', 'onLongPress:', 'CameraFit.coordinates(',
                   '_placeMapController.dispose()', 'DedaRegisteredPlacesStore.readAll()',
                   'DedaTaskEvent.mapOpened', 'DedaPreferences.defaultMapStyle',
                   'DedaMapPlaceMarker(', 'PolylineLayer(', 'widget.initialDestination'), 'free-map')
    require(main, ('maxCacheSize: 128 * 1024 * 1024,',), 'native-map-cache')
    if require_bound:
        require(core, ('dedaRunSectionVoid(', 'DedaSectionOperationContext.wait(',
                       'timeLimit: Duration(seconds: 12)'), 'GPS-existing-lifetime')
        if main.count('Geolocator.getCurrentPosition(') != reference.count('Geolocator.getCurrentPosition('):
            raise ValueError('MAP_FOUNDATION_GPS_CALLSITE_COUNT')
        if main.count('timeLimit: Duration(seconds: 12)') != 8:
            raise ValueError('MAP_FOUNDATION_GPS_CANCELLATION_COUNT')
        if main.count('Geolocator.getPositionStream(') != reference.count('Geolocator.getPositionStream('):
            raise ValueError('MAP_FOUNDATION_LIVE_GPS_STREAM_COUNT')
    return inventory


# Part 2: prove that the already integrated search screens and services differ
# from the immutable archive only by the existing approved lifetime/GPS binder.
# No operational source changes, no new search/cache/provider or account lane.
PART2_WIDGETS = ('NearbyPlacesPage', 'DedaPlaceSearchPage',
                 'PlaceDetailsPage', 'DedaMapPlaceMarker')
PART2_STATES = ('_NearbyPlacesPageState', '_DedaPlaceSearchPageState',
                '_PlaceDetailsPageState')
PART2_UNCHANGED = ('deda_geo_window.dart', 'deda_geo_firestore_reader.dart',
                   'deda_place_logo.dart', 'deda_place_palette.dart',
                   'deda_place_activity_symbol.dart', 'deda_place_engagement_bar.dart',
                   'deda_place_suggestions.dart')
PART2_GUARDED = ('places_service.dart', 'deda_place_engagement_service.dart',
                 'deda_place_branding_service.dart')


def part2_expected(reference, archive_member):
    from bind_location_entries import bind as bind_location
    from bind_all_sections import bind_file, bind_service
    # GPS patch was applied before the shared State lifetime transformation.
    # Apply to the complete archive because the existing GPS binder validates
    # all eight original call sites; never alter its anchors or its policy.
    gps = bind_location(reference)
    expected = {}
    for name in PART2_WIDGETS:
        expected[name] = member(reference, 'class ' + name + ' ')
    for name in PART2_STATES:
        original = member(gps, 'class ' + name + ' ')
        bound, report = bind_file("import 'dart:async';\n" + original)
        if len(report) != 1 or report[0]['binding'] != 'section-lifetime':
            raise ValueError('MAP_PART2_EXPECTED_SECTION_BINDING:' + name)
        expected[name] = member(bound, 'class ' + name + ' ')
    for name in PART2_UNCHANGED:
        expected[name] = archive_member('lib/' + name)
    for name in PART2_GUARDED:
        expected[name] = bind_service(archive_member('lib/' + name))
    return expected


def part2_equal(name, expected, actual):
    import difflib
    # Strict whole-member comparison: do not whitelist arbitrary edits merely
    # because they contain a guard name. Preserve all original behavior tokens.
    if tokens(expected) != tokens(actual):
        difference = difflib.unified_diff(
            expected.splitlines(), actual.splitlines(),
            fromfile='archive-plus-approved-binders/' + name,
            tofile='assembled/' + name, lineterm='', n=3)
        print('\n'.join(list(difference)[:100]))
        raise ValueError('MAP_PART2_UNEXPLAINED_TOKEN_DRIFT:' + name)
    # The eleven originally exact members must remain byte-for-byte identical.
    if name in PART2_WIDGETS + PART2_UNCHANGED and expected != actual:
        raise ValueError('MAP_PART2_EXACT_MEMBER_DRIFT:' + name)


def audit_part2(project, main, reference):
    spec = importlib.util.spec_from_file_location(
        'map_part2_archive', ROOT/'tools/app_stability/app_package/bind_stage2_profile_owner_2026_11_23.py')
    profile = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(profile)
    expected = part2_expected(reference, profile.archived_profile_member)
    actual = {name: member(main, 'class ' + name + ' ')
              for name in PART2_WIDGETS + PART2_STATES}
    actual.update({name: (project/'lib'/name).read_text()
                   for name in PART2_UNCHANGED + PART2_GUARDED})
    if set(expected) != set(actual) or len(actual) != 17:
        raise ValueError('MAP_PART2_INVENTORY_INCOMPLETE')
    failed = []
    for name, body in expected.items():
        try:
            part2_equal(name, body, actual[name])
            print('MAP_PART2_PARITY_PASS', name, digest(actual[name]))
        except ValueError as error:
            failed.append(str(error))
    if failed:
        raise ValueError('MAP_PART2_STOP:' + ';'.join(failed))
    # Negative controls: guard loss and changes to provider/palette must fail.
    for name, before, after in (
        ('_DedaPlaceSearchPageState', 'dedaSectionExpiredView()', 'otherExpiredView()'),
        ('places_service.dart', 'https://overpass-api.de/api/interpreter',
         'https://different.invalid/api/interpreter'),
        ('deda_place_palette.dart', '0xFFD83C46', '0xFFFFFFFF'),
    ):
        body = actual[name]
        changed = body.replace(before, after, 1)
        if changed == body:
            raise ValueError('MAP_PART2_NEGATIVE_CONTROL_ANCHOR:' + name)
        try:
            part2_equal(name, expected[name], changed)
        except ValueError:
            pass
        else:
            raise ValueError('MAP_PART2_NEGATIVE_CONTROL_ACCEPTED:' + name)
    print('PASS_STAGE2_MAP_PART2_17_MEMBERS_EXISTING_BINDERS_PARITY_NO_RUNTIME_CHANGE')



# Part 3: use the original ordered integration steps on the protected archive.
# The audit compares entire classes, including every original storage key,
# ownership check, publish/availability action and navigation callback.
PART3_EXACT = ('OwnerPlacePage', 'PersonalPlaceEditorPage', 'PersonalPlacesPage',
               'DedaPersonalPlace', 'SavedPlacesPage', 'DedaMakaniPage')


def part3_expected(reference):
    from bind_auth_runtime import bind_owner_place_load
    from bind_location_entries import bind as bind_location
    from bind_all_sections import bind_file, bind_main_data_helpers
    from bind_private_data import bind_source as bind_private
    # Same relative order as restore_deda_stability_baseline and
    # bind_section_entries. No new runtime bindings are written.
    owner = bind_owner_place_load(reference)
    gps = bind_location(owner)
    bound, _ = bind_file(gps)
    data = bind_private(bind_main_data_helpers(bound))
    return {name: member(reference if name in PART3_EXACT else data,
                         'class ' + name + ' ')
            for name in INVENTORY['3']}


def part3_equal(name, expected, actual):
    import difflib
    if tokens(expected) != tokens(actual):
        diff = difflib.unified_diff(
            expected.splitlines(), actual.splitlines(),
            fromfile='archive-plus-approved-binders/' + name,
            tofile='assembled/' + name, lineterm='', n=3)
        print('\n'.join(list(diff)[:120]))
        raise ValueError('MAP_PART3_UNEXPLAINED_TOKEN_DRIFT:' + name)
    if name in PART3_EXACT and expected != actual:
        raise ValueError('MAP_PART3_EXACT_MEMBER_DRIFT:' + name)


def audit_part3(project, main, reference):
    expected = part3_expected(reference)
    if len(expected) != 13:
        raise ValueError('MAP_PART3_INVENTORY_INCOMPLETE')
    actual = {name: member(main, 'class ' + name + ' ')
              for name in expected}
    failed = []
    for name, body in expected.items():
        try:
            part3_equal(name, body, actual[name])
            print('MAP_PART3_PARITY_PASS', name, digest(actual[name]))
        except ValueError as error:
            failed.append(str(error))
    if failed:
        raise ValueError('MAP_PART3_STOP:' + ';'.join(failed))
    # Controls: do not accept missing owner proof, bypassed private-data
    # bridge, or a disabled section-lifetime check.
    for name, before, after in (
        ('_OwnerPlacePageState', 'expectedAccountKey: recoveryAccountKey',
         'expectedAccountKey: otherAccountKey'),
        ('DedaPlacesStore', 'DedaPrivateDataBridge.readList',
         'otherPrivateDataBridge.readList'),
        ('_PersonalPlacesPageState', 'DedaPrivateDataBridge.write',
         'otherPrivateDataBridge.write'),
        ('_SavedPlacesPageState', 'dedaSectionExpiredView()',
         'otherExpiredView()'),
    ):
        changed = actual[name].replace(before, after, 1)
        if changed == actual[name]:
            raise ValueError('MAP_PART3_NEGATIVE_CONTROL_ANCHOR:' + name)
        try:
            part3_equal(name, expected[name], changed)
        except ValueError:
            pass
        else:
            raise ValueError('MAP_PART3_NEGATIVE_CONTROL_ACCEPTED:' + name)
    print('PASS_STAGE2_MAP_PART3_13_MEMBERS_OWNER_STORAGE_AND_LIFETIME_PARITY')



# Part 4: reconstruct the approved location account/section guards, not an
# alternate sending pipeline. Compare entire UI classes and shared backend
# operations in the assembled application, without performing any live send.
PART4_EXACT = ('DedaShareLocationPage', 'DedaReceivedLocationsPage')



def part4_later_share_reference(main):
    # Read-only reconstruction of the location-only edits from the previously
    # verified 100410 and 100411 binders. This runs on reference text only.
    # Preserve exact anchors, not a permissive list of allowed changes.
    from bind_weekly_100410_unified_active_id import one
    from bind_weekly_100411_friend_copy_share import once
    def call_end(source,start):
        depth=0
        for i in range(start,len(source)):
            if source[i]=='(': depth+=1
            elif source[i]==')':
                depth-=1
                if depth==0:
                    return i+2 if source[i+1:i+2]==',' else i+1
        raise ValueError("unclosed Dart call")

    # The assembled original already has two QA32 per-section wrappers.
    # Remove their separate resolution/fallback to the retired original ID.
    flag="// DEDA_QA32_SHARE_SENDER_VERIFIED_ACTIVE_ID_VISUAL_ONLY"
    if main.count(flag)!=1:
        raise ValueError("assembled owner's location ID wrapper not unique")
    begin=main.index("DedaQa32ActiveAccountScope(",main.index(flag))
    finish=call_end(main,begin)
    assert "originalId: _personalId" in main[begin:finish]
    assert "'معرفي الشخصي'" in main[begin:finish]
    main=main[:begin]+"""DedaUnifiedActiveIdBuilder100410(
                            originalId:_personalId,
                            builder:(context,active) => active==null
                              ? const SizedBox(height:48,child:Center(
                                  child:Text('جارِ تأكيد الآيدي...',
                                    textDirection:TextDirection.rtl)))
                              : _idCard(
                                  title:dedaText('معرفي الشخصي','My personal ID'),
                                  id:active,icon:Icons.person),
                          ),"""+main[finish:]
    marker="// DEDA_QA32_RECEIVED_PERSONAL_LOCATION_VERIFIED_SENDER_ALIAS_NO_DEPLOY"
    if main.count(marker)!=1:
        raise ValueError("assembled recipient sharing display anchor changed")
    begin=main.index("DedaSixReceivedIdentity(",main.index(marker))
    finish=call_end(main,begin)
    if "originalId: senderId" not in main[begin:finish]:
        raise ValueError("sender personal ID resolver not safe to replace")
    main=main[:begin]+"""DedaUnifiedActiveIdLabel100410(
                            originalId:senderId,
                            style:const TextStyle(
                              color:Color(0xFF5C635D),
                              fontWeight:FontWeight.w700)),"""+main[finish:]
    # Security regression caught by the added location identity tests.
    # An existing page must not use a changed/logged-out account, even if
    # GPS and permission callbacks complete long after the switch.
    share_begin=main.index("class DedaShareLocationPage")
    share_end=main.index("class DedaReceived",share_begin) if "class DedaReceived" in main[share_begin:] else main.index("Widget _shareCard(",share_begin)
    share=main[share_begin:share_end]
    if "Future<void> _send() async {" not in share:
        raise ValueError("location sender guard could not be reviewed")
    share=one(share,
        """  String _personalId = '';""",
        """  String _personalId = '';
  late final String _ownerPhoneAtOpen;""",
        "account isolation fixed when opening share page")
    share=one(share,
        """    _personalId = DedaBackend.personalShareIdForPhone(DedaPreferences.phone);""",
        """    _ownerPhoneAtOpen = DedaPreferences.phone;
    _personalId = DedaBackend.personalShareIdForPhone(DedaPreferences.phone);""",
        "snapshot opening identity for old page protection")
    send=share.index("Future<void> _send() async {")
    body=send+len("Future<void> _send() async {")
    share=share[:body]+"""
    // A page opened under A cannot validate or send anything under B/logout.
    if (!DedaPreferences.isLoggedIn ||
        DedaPreferences.phone != _ownerPhoneAtOpen) return;
"""+share[body:]
    # Only the GPS branch awaits before making the original backend call.
    # Guard IMMEDIATELY after its await, instead of matching an obsolete
    # indentation of createLocationShare in the assembled real owner source.
    # The place branch is synchronous until the same backend call, so its
    # account protection is the entry guard above.
    if "createLocationShare(" not in share:
        raise ValueError("original location-share backend operation missing")
    # Verified exact assembled 100409 call (from GitHub QA run 18):
    # _currentPosition runs inside SectionOperationContext.wait, so do not
    # search for a direct await. Keep all existing snapshot/route protections.
    gps_before="        final position = await DedaSectionOperationContext.wait(() => _currentPosition());"
    share=one(share,gps_before,
              gps_before+"""
        // Late GPS must never resume a share for B from A's open page.
        if (!mounted || !DedaPreferences.isLoggedIn ||
            DedaPreferences.phone != _ownerPhoneAtOpen) return;""",
              "actual assembled GPS wrapper account isolation")
    main=main[:share_begin]+share+main[share_end:]

    text = main
    share_begin=text.index("class DedaShareLocationPage")
    share_end=text.index("class DedaReceived",share_begin)
    share=text[share_begin:share_end]
    send_begin=share.index("Future<void> _send() async")
    send_end=share.index("  Widget _idCard(",send_begin)
    send=share[send_begin:send_end]
    send=once(send,
        "if (!DedaBackend.isValidPersonalShareId(recipient)) {",
        "if (DedaFriendIdCopy100411.exactCopyValue(recipient) == null) {",
        "accept structurally valid copyable premium input")

    # Route identity AFTER the location acquisition, immediately BEFORE
    # the existing backend send. Never delay the original GPS path or change
    # its busy flag, permissions, account/session sequencing and user prompts.
    backend="await DedaSectionOperationContext.wait(() => DedaBackend.createLocationShare("
    if send.count(backend)!=1:
        raise ValueError("100411 exact backend send count="+str(send.count(backend)))
    at=send.index(backend)
    guard="""
      // Canonical personal IDs always take priority over premium aliases.
      // Server comparison is only needed once GPS is ready. Firebase may
      // be deliberately uninitialized in legacy widget tests: preserve
      // their original backend-not-ready error and the original GPS flow.
      String canonicalRecipient = recipient;
      if (DedaBackend.isReady) {
        final direct = DedaBackend.isValidPersonalShareId(recipient)
            ? await DedaSectionOperationContext.wait(
                () => DedaBackend.locationShareIdInfo(recipient))
            : null;
        if (direct == null || direct['kind'] != 'personal') {
          final resolved = await DedaSectionOperationContext.wait(
              () => DedaQa32PublicRecipientResolver.resolveActiveAlias(
                  recipient));
          if (resolved == null ||
              !DedaBackend.isValidPersonalShareId(resolved)) {
            throw StateError('recipient-share-id-not-found');
          }
          canonicalRecipient = resolved;
        }
        if (!_locationAccountCurrent() ||
            !DedaPreferences.isLoggedIn ||
            DedaPreferences.phone != _ownerPhoneAtOpen) return;
        DedaAuthRuntime.checkSnapshot(requestPrincipal);
        if (canonicalRecipient == personalId) {
          throw StateError('share-self-recipient');
        }
      }
      """
    send=send[:at]+guard+send[at:]
    send=once(send,"recipientPublicId: recipient,",
                   "recipientPublicId: canonicalRecipient,",
                   "server-authoritative canonical routing for location")
    share=share[:send_begin]+send+share[send_end:]
    text=text[:share_begin]+share+text[share_end:]
    return text

def part4_expected(reference):
    from bind_auth_runtime import bind_main
    from bind_location_entries import bind as bind_location
    from bind_location_identity import bind as bind_identity
    from bind_all_sections import bind_file
    guarded, _ = bind_file(bind_identity(bind_location(bind_main(reference))))
    guarded = part4_later_share_reference(guarded)
    return {name: member(reference if name in PART4_EXACT else guarded,
                         'class ' + name + ' ')
            for name in INVENTORY['4']}


def part4_equal(name, expected, actual):
    import difflib
    if tokens(expected) != tokens(actual):
        diff = difflib.unified_diff(
            expected.splitlines(), actual.splitlines(),
            fromfile='archive-plus-approved-binders/' + name,
            tofile='assembled/' + name, lineterm='', n=3)
        print('\n'.join(list(diff)[:100]))
        raise ValueError('MAP_PART4_UNEXPLAINED_TOKEN_DRIFT:' + name)
    if name in PART4_EXACT and expected != actual:
        raise ValueError('MAP_PART4_EXACT_MEMBER_DRIFT:' + name)


def audit_part4(project, main, reference):
    from bind_auth_runtime import bind_backend, body_range
    expected = part4_expected(reference)
    if len(expected) != 4:
        raise ValueError('MAP_PART4_INVENTORY_INCOMPLETE')
    actual = {name: member(main, 'class ' + name + ' ') for name in expected}
    for name in expected:
        part4_equal(name, expected[name], actual[name])
        print('MAP_PART4_PARITY_PASS', name, digest(actual[name]))
    # Server-facing read/decision/sending contracts are compared against the
    # immutable backend with its original approved auth-await transformation.
    # Identity registration has additional later reviewed UID protections and
    # is deliberately not replaced with an older archive implementation.
    spec = importlib.util.spec_from_file_location(
        'map_part4_archive', ROOT/'tools/app_stability/app_package/bind_stage2_profile_owner_2026_11_23.py')
    profile = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(profile)
    old_backend = bind_backend(profile.archived_profile_member('lib/deda_backend.dart'))
    backend = (project/'lib/deda_backend.dart').read_text()
    for name in ('locationShareIdInfo', 'createLocationShare', 'decideLocationShare'):
        def future_body(src):
            opening, closing, _, start = body_range(src, name)
            return src[start:closing+1]
        part4_equal(name, future_body(old_backend), future_body(backend))
        print('MAP_PART4_BACKEND_PARITY_PASS', name)
    for marker in ('static Stream<List<Map<String, dynamic>>> locationSharesStream(',
                   'static Stream<int> pendingLocationSharesCountStream('):
        part4_equal(marker, member(old_backend, marker), member(backend, marker))
        print('MAP_PART4_BACKEND_PARITY_PASS', marker)
    opening, closing, _, _ = body_range(backend, 'ensureLocationShareIdentity')
    registration = backend[opening:closing]
    require(registration, ('_ensureOwnerSessionForAccountKey(accountKey)',
                           'personalShareIdForPhone(phone)', 'placeShareIdForPhone(phone)',
                           'original-share-uid-conflict-recovery-required',
                           'canStageOriginalShareProjection(',
                           'original-share-session-changed-before-user-write',
                           'original-share-session-changed-before-route-write'), 'share-owner-registration')
    home.verify_home(member(main, 'class _HomePageState '))
    for name, before, after in (
        ('_DedaShareLocationPageState', 'DedaAuthRuntime.checkSnapshot(requestPrincipal)',
         'otherCheck(requestPrincipal)'),
        ('_DedaReceivedLocationsPageState', 'dedaSectionExpiredView()',
         'otherExpiredView()'),
    ):
        changed = actual[name].replace(before, after, 1)
        if changed == actual[name]:
            raise ValueError('MAP_PART4_NEGATIVE_CONTROL_ANCHOR:' + name)
        try:
            part4_equal(name, expected[name], changed)
        except ValueError:
            pass
        else:
            raise ValueError('MAP_PART4_NEGATIVE_CONTROL_ACCEPTED:' + name)
    print('PASS_STAGE2_MAP_PART4_UI_BACKEND_SHARE_CONTRACT_AND_ACCOUNT_LIFETIME_PARITY')


def audit(project):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('MAP_FOUNDATION_REQUIRES_DISPOSABLE_FULL_ASSEMBLY')
    main = (project/'lib/main.dart').read_text()
    reference = home.archive_reference()
    inventory = verify(main, reference)
    # Source files are tracked, not asserted immutable after known earlier
    # auth/section overlays. Every later part must compare them independently.
    for file in ('places_service.dart', 'deda_geo_window.dart',
                 'deda_geo_firestore_reader.dart', 'deda_place_logo.dart',
                 'deda_place_palette.dart', 'deda_place_activity_symbol.dart',
                 'deda_place_engagement_bar.dart', 'deda_place_engagement_service.dart',
                 'deda_place_branding_service.dart', 'deda_place_suggestions.dart',
                 'deda_route_hazard_corridor.dart', 'admin_place_map.dart'):
        path = project/'lib'/file
        if not path.is_file():
            raise ValueError('MAP_FOUNDATION_MISSING_MEMBER:' + file)
        print('MAP_MEMBER_SHA256', file, hashlib.sha256(path.read_bytes()).hexdigest())
    print('MAP_FIVE_PART_INVENTORY=' + json.dumps(inventory, sort_keys=True))
    print('PASS_STAGE2_MAP_PART1_PROVIDER_CACHE_GPS_CORE_VISUAL_PARITY_READ_ONLY')
    audit_part2(project, main, reference)
    audit_part3(project, main, reference)
    audit_part4(project, main, reference)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    args = parser.parse_args()
    audit(args.project)
