# DEDA map scalability — verified progress on 2026-10-08

## Protected stable mobile version

- Stable field-tested APK: **DEDA 100318**.
- Immutable rollback branch: `backup-100318-field-tested-user-heading-camera-2026-10-08`.
- Navigation camera, arrow, destination flag, GPS, road hazards and existing Firestore rules **unchanged** by this stage.
- New code on `map-scalability-public-search-coalesce-2026-10-08` is **development branch only**, not a released APK.

## Verified step A — offline source scalability baseline

- All source safety/audit checks passed in [GitHub Actions #37805720129](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37805720129).
- Recorded high-risk scale limits: public OSM tiles, public OSRM/Valhalla routing, Overpass/Nominatim search, globally capped 500 hazard reads, globally capped 500 published places.
- No public endpoint load test was run, no production data or rules changed.

## Verified step B — same-device public-search request coalescing

- Created bounded `DedaRequestCoalescer<T>` and wired it **only** to `PlacesService` public name/nearby lookups.
- Requests for an identical public search while pending share one in-flight fetch instead of sending duplicates.
- Valid nonempty public results cached **45 seconds**, at most **24 keys**, and **only when the list contains at most 100 places**.
- Errors, empty responses and huge responses are not cached. Each consumer gets its own list copy, so UI sorting cannot mutate the cache.
- No caching of user live GPS, camera, planned route, road hazards or DEDA registered-business availability.
- Flutter tests cover 100 simultaneous identical calls, 45s expiry, retry after error, empty and huge result safeguards, distinct keys and LRU eviction.
- All Flutter tests, Dart static analysis, source integration tests and 100318 protected-file comparison passed in [GitHub Actions #37806348738](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/37806348738).
- **Important:** This is per-device protection, *not* proof of server capacity at 100 or 10,000 concurrent users.

## Remaining must-do before declaring map ready for high concurrency

1. Safely replace unbounded nationwide client queries for published businesses and hazards with tested location-scoped index-backed access. This involves Firestore migration, rules and indexes; do not alter hazard correctness or hide older entries.
2. Choose a legally and operationally supportable map-tile, POI search and routing delivery capacity plan for expected traffic; public endpoints do not provide an established production-level SLA for DEDA.
3. Measure allowed test load against approved infrastructure (not public OSM/OSRM/Overpass) and confirm p95, error/429 rate, Firebase read costs, network behavior, and navigation regression on real devices.
4. Deliver a **single consolidated APK** after these changes and full regression testing; do not publish automatically.

Next operation is infrastructure/data design, **not** changing the live navigation camera or GPS.

