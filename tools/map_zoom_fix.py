from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

integrated = """                  initialCameraFit: fitPoints.length < 2
                      ? null
                      : CameraFit.coordinates(
                          coordinates: fitPoints,
"""

if integrated in text:
    print("DEDA map auto-fit is integrated in source; no patch needed.")
    raise SystemExit(0)

old = """                  initialCameraFit: visibleMapSearchResults.isEmpty
                      ? null
                      : CameraFit.coordinates(
                          coordinates: <LatLng>[
                            point,
                            ...visibleMapSearchResults.map(
                              (place) => place.location,
                            ),
                          ],
                          padding: const EdgeInsets.all(55),
                          maxZoom: 15,
                        ),
"""

new = """                  initialCameraFit: selectedDestination != null
                      ? CameraFit.coordinates(
                          coordinates: <LatLng>[
                            point,
                            selectedDestination!,
                          ],
                          padding: const EdgeInsets.all(55),
                          maxZoom: 15,
                        )
                      : visibleMapSearchResults.isEmpty
                          ? null
                          : CameraFit.coordinates(
                              coordinates: <LatLng>[
                                point,
                                ...visibleMapSearchResults.map(
                                  (place) => place.location,
                                ),
                              ],
                              padding: const EdgeInsets.all(55),
                              maxZoom: 15,
                            ),
"""

count = text.count(old)
if count != 1:
    raise SystemExit(
        f"DEDA map auto-fit patch: expected exactly one legacy match, found {count}"
    )

path.write_text(text.replace(old, new, 1))
