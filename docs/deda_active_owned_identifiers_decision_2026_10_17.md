# DEDA | Owner-approved decision: owned identifiers and one active identifier
Date: 2026-10-17. Planning/design decision only; not a claim of completed implementation. Do NOT deploy or change live Firestore rules or wallet data without separately approved migration/tests.

## Non-negotiable user requirements
1. Every DEDA account keeps its original identifier forever and owns each subsequently purchased or administrator-gifted premium identifier permanently unless an explicit separately defined authorized revocation rule is adopted. Switching display identifiers does not delete, refund, resell, or transfer former IDs.
2. One and only one owned identifier is selected as `activeIdentifier` at a time. Choosing a different owned ID is the user-controlled switching operation; it must actually work, not merely change the profile graphic.
3. The active identifier is displayed consistently **throughout DEDA**: own profile, public profile seen by others, friend listings, outgoing shared-location sender metadata, incoming shared-location recipient metadata, ID copy/share actions, search results and any other user-facing identifier surfaces.
4. Entering the currently active ID must resolve to the correct user for friend lookup, send/receive location sharing, public profile display, and any other ID-based flow. Active ID may be premium purchased or administrator-gifted. Account ID can be changed back to the original on request.
5. Historical owned IDs MUST remain reserved and should continue to safely resolve as private aliases to the same stable account UID so saved friend references and older ID-based links keep functioning. Alias use does **not** make an old alias the publicly displayed active ID. Whether additional alias routing rules are needed must be verified against existing app usage.
6. Never change Firebase Auth UID to switch a public identifier. Keep friendship, location-sharing permissions and expiration, levels and XP, points, diamonds, purchases, gifted items and their histories bound to stable user identity.
7. A location lookup alone must NOT grant tracking or location access. Preserve user consent, send/share operations, receiver ID verification, 30-minute expiration as configured, and permissions.
8. Identifier uniqueness must be global and atomic: ownership registry prevents duplicates or races. Assignment/purchase/gifting/switching must validate actual account ownership and avoid collisions or impersonation; use server-authoritative and auditable operations. Do not trust arbitrary client-supplied names.
9. Profile/edit UI: top-left redundant ID-copy icon is to be replaced with edit pencil; ID-copy stays in the ID chip. Provide 'My identifiers' in edit/account page, showing original + all purchased/gifted identifiers, clear active indicator and an explicit Select/Activate action (confirm when switching). Do not conflate changing the active ID with changing the immutable account UID.
10. On failed activation, keep the old active ID and avoid partial updates; client UI waits for server confirmation. Compatibility testing must cover old identifiers, all entry points, send/receive location, public profile, friends, and balance invariants.
11. Do not introduce static mockup balances/levels or modify wallet/point/reward systems. Work in an isolated GitHub branch, preserve owner-approved stable recovery branch; explicit owner approval before Play publishing.

## Important implementation distinction
UI mockup and existing DEDA LAB saved IDs are NOT proof that end-to-end ownership, account routing or activation in Flutter+Firestore is already present. Audit real code and production-compatible rules before claiming the new workflow is live.

## Working context
Working branch: `profile-royal-step1-3avatars-4frames-2026-10-17`
Recovery branch: `backup-deda-100340-before-profile-royal-2026-10-17`
Royal hero UI staged/tested separately. This ID rule is a requirements checkpoint for a future carefully tested implementation; no live updates authorized.
