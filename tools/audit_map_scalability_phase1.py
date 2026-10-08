#!/usr/bin/env python3
"""DEDA map scalability: offline, read-only preflight. Makes NO network requests."""
from pathlib import Path
import json, re, sys

root=Path(__file__).resolve().parents[1]
main=(root/"lib/main.dart").read_text()
places=(root/"lib/places_service.dart").read_text()
backend=(root/"lib/deda_backend.dart").read_text()
road=(root/"lib/deda_road_class_lookup.dart").read_text()

checks=[
  ("tile_cache_local", "BuiltInMapCachingProvider.getOrCreateInstance" in main
    and "maxCacheSize: 128 * 1024 * 1024" in main, "Per-device tile cache, 128MiB"),
  ("obsolete_tiles_cancelled", "abortObsoleteRequests: true" in main,
    "Obsolete tile requests are cancelled when panning"),
  ("navigation_single_gps_stream", main.count("Geolocator.getPositionStream(") == 1,
    "Only one navigation GPS subscription in source"),
  ("hazard_inflight_guard", "_hazardsLoading" in main
    and "if (!tripStarted || !DedaBackend.isReady || _hazardsLoading)" in main,
    "Prevents overlapping hazard fetches inside a trip"),
  ("hazard_fetch_throttled", "Duration(seconds: 45)" in main
    and "_lastHazardFetchPoint" in main, "Hazard fetching gated by time/distance"),
  ("route_fallback", "router.project-osrm.org" in main
    and "valhalla1.openstreetmap.de" in main, "Public routing fallback exists"),
  ("places_fallback", "nominatim.openstreetmap.org" in places
    and len(re.findall(r"https://overpass",places)) >= 3,
    "Place search has Nominatim and Overpass fallback endpoints"),
  ("hazard_limit_guard", re.search(r"collection\('road_hazards'\)[\s\S]{0,130}\.limit\(500\)",backend) is not None,
    "Hazard request currently bounded to at most 500 documents"),
  ("published_limit_guard", re.search(r"collection\('published_places'\)[\s\S]{0,140}\.limit\(500\)",backend) is not None,
    "Published-place query currently capped at 500 documents"),
  ("optional_road_class_nonblocking", "Never blocks GPS" in road
    and "if (hazards.isEmpty)" in road, "Road class enrichment optional"),
  ("build_100318_preserved", (root/"tools/build_100318_user_heading_camera.sh").exists(),
    "100318 independent successful build recipe present"),
]
fail=[key for key,ok,desc in checks if not ok]
report={
  "purpose":"Read-only map scaling baseline; not a performance/load test",
  "baseline":"DEDA 100318, field-tested checkpoint",
  "tested_with":"offline source invariants; no requests to public providers",
  "checks":[{"id":k,"passed":ok,"evidence":desc} for k,ok,desc in checks],
  "known_risks":[
    {"id":"public_tiles","level":"high","reason":"Direct clients request public OpenStreetMap/Esri tiles; local cache does not aggregate across different users"},
    {"id":"public_routing","level":"high","reason":"OSRM/Valhalla endpoints are public and no provider-side capacity SLA is established"},
    {"id":"public_search","level":"high","reason":"Overpass/Nominatim search has fallback but no centralized cache/global request budget"},
    {"id":"global_hazards","level":"high","reason":"Every active navigator may read up to 500 globally active Firestore hazards per fetch; client filters only afterward"},
    {"id":"published_places_cap","level":"high","reason":"Published places query caps at 500 globally, which becomes a completeness problem as businesses grow"}
  ],
  "safety":"No map, GPS, camera, route, flag, Firestore rules, or API changes applied"
}
out=root/"map_scale_phase1_audit.json"
out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
for k,ok,desc in checks: print(f'{"PASS" if ok else "FAIL"} {k}: {desc}')
print(f'AUDIT known_capacity_risks={len(report["known_risks"])}')
print(f'AUDIT source_checks_passed={sum(ok for _,ok,_ in checks)}/{len(checks)}')
print("NOTE: No actual concurrent-user limit can be asserted without service capacity, permitted testing, and production metrics.")
sys.exit(bool(fail))
