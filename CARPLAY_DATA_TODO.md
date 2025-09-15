# CarPlay Data Structure and Fallbacks

This document describes the expected iOS CarPlay data for `cordova-plugin-auto`, how it mirrors Android Auto, and what fallbacks are applied when data is missing or unusable. Use it to validate the files your app writes into `Library/NoCloud`.

## Files read (priority order)

- AUTO_NAVIGATION (extensionless JSON)
  - Searched in: `Library/NoCloud/`, `Library/NoCloud/navigation/`
  - Bundle fallback: `navigation/AUTO_NAVIGATION` (or `AUTO_NAVIGATION.json`) inside app bundle
- AUTO_NAVIGATION_LIBRARY (extensionless JSON)
  - Searched in: `Library/NoCloud/`, `Library/NoCloud/navigation/`, `Library/NoCloud/data/navigation/`
  - Bundle fallback: `navigation/AUTO_NAVIGATION_LIBRARY`

The provider logs each load attempt with `[CDVPlaylistProvider]` prefixes.

## Expected JSON schemas

### 1) `AUTO_NAVIGATION`
- Pure sections model, each section becomes a CarPlay Tab (`CPListTemplate`).
- Minimal schema:
```json
[
  {
    "text": "Playlists",
    "items": [
      { "id": "pl_123", "name": "Top 50", "description": "Trending" },
      { "id": "pl_456", "name": "Chill", "description": "Relax" }
    ]
  },
  {
    "text": "Artists",
    "items": [
      { "id": "ar_1", "name": "Adele" },
      { "id": "ar_2", "name": "Drake" }
    ]
  }
]
```
- Required:
  - Section title in `text` (non-empty). If empty, iOS falls back to `Section N`.
  - Each item should include a non-empty display name in `name` or `title`.
  - When user selects an item, the plugin tries to resolve tracks if it represents a playlist-like object (via `id`).

### 2) `AUTO_NAVIGATION_LIBRARY`
- Mirrored Android library sections (Playlists, Albums, Artists, etc.).
- Minimal schema for each section:
```json
[
  {
    "text": "Playlists",
    "items": [
      { "id": "pl_123", "name": "Top 50", "description": "Trending" }
    ]
  },
  {
    "text": "Albums",
    "items": [
      { "id": "al_222", "name": "1989 (Taylor's Version)" }
    ]
  }
]
```
- Same requirements as `AUTO_NAVIGATION` regarding `text` and item name.

## iOS build behavior (mirrors Android)

1. Build tabs from `AUTO_NAVIGATION` if present and valid.
2. If empty/absent, build tabs from `AUTO_NAVIGATION_LIBRARY`.
3. If still nothing usable, build a single "Playlists" tab from the extracted playlists provider.
4. If no data at all, add a static "Browse" tab with placeholder items.

All tabs now set:
- A guaranteed non-empty `tabTitle` (fallbacks to `Section N`).
- A default `tabImage` (system symbol `music.note.list` on iOS 13+), to avoid "More" placeholders.

## Logging added

Look for `[CarPlay]` logs:
- `[CarPlay] [NAV] building section title=... items=...`
- `[CarPlay] [LIB] section idx=... title=... rawKeys=... items=...`
- `[CarPlay] [LIB][WARN] item with empty name. keys=...`
- `[CarPlay] [LIB] building section title=... items=...`
- `[CarPlay] Final tabs count=X titles=[... ]`
- Fallbacks:
  - `[CarPlay] setupTemplates: library sections loaded count=X`
  - `[CarPlay][FALLBACK] No valid templates found. Adding static Browse tab.`

Provider logs:
- `[CDVPlaylistProvider] loadNavigationFromJSON: ...`
- `[CDVPlaylistProvider] loadLibrarySectionsFromJSON: ...`

## Common data issues and how to fix

- Empty section titles -> set `text` string per section. iOS falls back to `Section N` but you should provide a proper title.
- Items missing display text -> provide `name` or `title` per item. Otherwise CarPlay shows generic "Item" and logs a warning.
- Item without actionable `id` -> the tap handler cannot load tracks. Provide a stable `id` for playlist-like items that the provider can resolve to tracks.
- Too many sections -> CarPlay shows up to 4 tabs (extra under "More"). Consider ordering/prioritizing sections or merging less important ones.

## Minimum viable data (no Android changes)

If your current Android library JSON already has `text` and `items` with `name` and `id`, it should work as-is on iOS with the new fallback. Ensure files are written to `Library/NoCloud` without `.json` extension (extensionless) to match iOS loader.

## Where to place files on iOS

- Simulator path example:
  `~/Library/Developer/CoreSimulator/Devices/<DEVICE_ID>/data/Containers/Data/Application/<APP_ID>/Library/NoCloud/`
- Place either:
  - `AUTO_NAVIGATION`
  - `AUTO_NAVIGATION_LIBRARY`
  - Optionally under `navigation/` or `data/navigation/` subfolders.

## Next steps for you

1. Run the app with CarPlay Simulator connected.
2. Inspect Xcode console for `[CarPlay]` and `[CDVPlaylistProvider]` lines.
3. If tabs still show as "More", check for empty titles or missing images in the logs.
4. Adjust your JSON to meet the minimal schema above.

If you want, share the logs and a sample of your current files; we’ll point out exactly what needs to change.
