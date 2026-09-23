from pathlib import Path

path = Path("tools/final_release_fix.py")
text = path.read_text()

start_marker = "owner_start = text.find("
end_marker = "# Keep the admin source stable in the repository and apply the release-only"
start = text.find(start_marker)
end = text.find(end_marker, start)

if start < 0 or end < 0:
    raise SystemExit("final_release_fix owner section markers not found")

replacement = """# The final owner-place flow already owns availability persistence and\n# server synchronization. Skip the obsolete release-only owner patch.\npath.write_text(text)\n\n# Build 111+ uses the first-class team/permissions system and central audit.\nif Path("lib/admin_team_pages.dart").exists():\n    print("DEDA admin team system detected; skipped legacy admin-history patch.")\n    raise SystemExit(0)\n\n"""

text = text[:start] + replacement + text[end:]
path.write_text(text)
print("Prepared final_release_fix.py for the final DEDA owner flow.")
