# Datastore Save Manager

## Personal saves
- Personal files are indexed by `Player.UserID`, so each account sees its own saves on any server.
- Players can save, load, rename, delete, and copy their personal builds.
- Admins can inspect another account by UserID, copy a save for review, and delete an inappropriate save. Personal save moderation is validated on the server.

## Permanent Admin Builds
- Administrators listed in `scripts/modules/Admins.luau` can publish a build using the `Publish Admin Build` button.
- Admin Builds are stored in a separate global datastore and are listed for every player in the `ADMIN BUILDS | GLOBAL TUTORIALS` panel.
- Any player can load or copy an Admin Build.
- Admin Builds cannot be deleted or renamed through the game, including by administrators. The server rejects delete attempts.
- The global library currently has a 100-build limit.

## Copy format and Base64
`Copy Data` returns the original compact JSON import string, so it can be pasted directly into the existing Import tool. Standard Base64 is not used because it expands data by roughly one third; it does not make the copied text smaller. Base64 decoding would add work without providing a size benefit.

## Storage layout
- Personal datastore: `UCBGSaves`; personal indexes use `u<userId>i` and chunks use `u<userId>f<fileId>c<chunk>`.
- Global datastore: `UCBGAdminBuilds`; its index uses `index` and chunks use `g<fileId>c<chunk>`.
- Data is split into 60,000-byte values, below Polytoria's documented 65,535-byte per-key limit.
- Application limits: 6 MB per file, 100 chunks per file, 100 personal files per account, and 100 global Admin Builds.
- Datastore requests are serialized and rate-limited. Chunking bypasses the per-key size ceiling, not datastore request-rate limits.

## UI layout
The save manager is smaller and shifted downward from screen center to reduce overlap with the chat and ESC/menu areas. It has separate Personal Saves and Admin Builds columns.

## Testing
Polytoria documents that datastore requests do not persist during local Creator testing. Test using an uploaded/published place in a live server.
