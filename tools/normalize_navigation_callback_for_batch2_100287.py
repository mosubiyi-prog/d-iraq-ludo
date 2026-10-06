from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

token = "onPositionChanged: (camera, _) {"
idx = text.find(token)
if idx < 0:
    raise SystemExit("100287 callback normalizer: callback start missing")

line_start = text.rfind("\n", 0, idx) + 1
comment = "// follow on the next GPS/animation frame."
comment_idx = text.find(comment, idx)
if comment_idx < 0:
    raise SystemExit("100287 callback normalizer: callback end comment missing")

closing = "                        },"
end_idx = text.find(closing, comment_idx)
if end_idx < 0:
    raise SystemExit("100287 callback normalizer: callback closing missing")
end_idx += len(closing)
if end_idx < len(text) and text[end_idx] == "\n":
    end_idx += 1

normalized = '''                        onPositionChanged: (camera, _) {
                          final zoom = camera.zoom;
                          if ((zoom - _displayMapZoom).abs() >= 0.08 && mounted) {
                            setState(() => _displayMapZoom = zoom);
                          }
                          // Active navigation always returns to heading-up live
                          // follow on the next GPS/animation frame.
                        },
'''

text = text[:line_start] + normalized + text[end_idx:]
path.write_text(text)
print("DEDA 100287 callback normalized for batch2 anchor.")
