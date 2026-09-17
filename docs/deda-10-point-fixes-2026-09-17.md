# DEDA ten-point review fixes — 2026-09-17

This checkpoint documents the reviewed changes applied on `places-v1` after the two-phone QA session:

- Prevent duplicate active place requests while one is pending/reviewing.
- Keep owner availability sourced from the published place for admin/live views.
- Search approved DEDA places by name before external map search.
- Use the signed-in account identity for support messages.
- Separate support workflow states/actions from place approval actions.
- Add admin replies for support tickets and expose replies to the owner.
- Link support tickets to the related DEDA place when available.
- Add read-only admin account review with audit logging.
- Make support image upload more robust and display uploaded/fallback images to admin.
- Format new approval sequence numbers with seven digits.

A backup branch exists from before these changes: `backup-2026-09-17-pre-10-fixes`.
