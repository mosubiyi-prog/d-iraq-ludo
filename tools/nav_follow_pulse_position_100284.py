from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

old_follow = '''                        onPositionChanged: (camera, hasGesture) {
                          if (tripStarted &&
                              hasGesture &&
                              _autoFollowMap &&
                              mounted) {
                            // A deliberate map gesture temporarily pauses live
                            // camera following. The existing recenter button is
                            // then shown; pressing it resumes automatic follow.
                            setState(() => _autoFollowMap = false);
                          }
                        },
'''
new_follow = '''                        onPositionChanged: (_, __) {
                          // During active navigation DEDA keeps live-follow
                          // enabled. A map gesture may change zoom briefly, but
                          // the next GPS/animation frame recenters the vehicle
                          // so the arrow remains fixed near the map center while
                          // the map moves underneath it.
                        },
'''
if old_follow not in text:
    raise SystemExit("100284: navigation gesture/follow anchor not found")
text = text.replace(old_follow, new_follow, 1)

old_speed = '''            if (tripStarted && !isLandscape)
              Positioned(
                top: 118,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
'''
new_speed = '''            if (tripStarted && !isLandscape)
              Positioned(
                top: _activeHazard != null ? 182 : 118,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
'''
if old_speed not in text:
    raise SystemExit("100284: portrait speed indicator anchor not found")
text = text.replace(old_speed, new_speed, 1)

old_pulse = '''            if (tripStarted && _activeHazard != null)
              Positioned(
                top: isLandscape ? 78 : 188,
                left: isLandscape ? 96 : 18,
                right: isLandscape ? 96 : 18,
                child: _buildHazardWarning(_activeHazard!),
              ),
'''
new_pulse = '''            if (tripStarted && _activeHazard != null)
              Positioned(
                // Keep Road Pulse directly below the turn instruction instead
                // of across the middle of the driving map. In portrait the
                // speed badge moves below it only while an alert is visible.
                top: isLandscape ? 78 : 108,
                left: isLandscape ? 96 : 18,
                right: isLandscape ? 96 : 18,
                child: _buildHazardWarning(_activeHazard!),
              ),
'''
if old_pulse not in text:
    raise SystemExit("100284: Road Pulse position anchor not found")
text = text.replace(old_pulse, new_pulse, 1)

path.write_text(text)
print("DEDA 100284 navigation follow + Road Pulse position patch applied.")
