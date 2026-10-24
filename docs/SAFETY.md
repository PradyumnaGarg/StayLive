# Safety and privacy

StayLive is designed to be easy to trust and easy to remove. This page lists everything it does to your Mac.

## What it never does

- It never asks for an administrator password and never runs anything as root.
- It never touches system files (`/System`, `/Library`) and works with System Integrity Protection fully on.
- It installs no kernel or system extensions, background daemons or login hooks (launch at login uses Apple's standard "Login Items" mechanism; it's on after the first launch and can be turned off in Settings or System Settings → General → Login Items).
- It makes **no network connections**: no analytics, no update checks, no uploads. Your videos never leave your Mac.
- It requests no privacy permissions (camera, microphone, screen recording, files outside the ones you pick).

## What it reads and writes

All paths are inside your own home folder.

| Path | What | Why |
|---|---|---|
| `~/Library/Application Support/StayLive/` | Your library (copies of imported videos, thumbnails, converted lock-screen videos, backups) and `library.json` | The app's own data |
| `~/Library/Preferences/<bundle id>.plist` | Settings (volume, pause on battery, current wallpaper…) | Standard app preferences |
| `~/Library/Preferences/com.apple.wallpaper.aerial.plist` | Two keys added: `AerialManifestForceLocal`, `AerialManifestLocalPathOverride` | Lock screen |
| `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json` | **Read only**: Apple's Aerial list, copied into StayLive's catalog | Lock screen |
| `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/staylive-entries.json` | **Created**: StayLive's catalog | Lock screen |
| `~/Library/Application Support/com.apple.wallpaper/aerials/videos/<wallpaper id>.mov`, `thumbnails/<wallpaper id>.png` | **Created**: your converted videos and their thumbnails | Lock screen |
| `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` | The Aerial choice is updated when you set a lock-screen video, the same change System Settings makes | Lock screen |
| `~/Library/Screen Savers/StayLive.saver` | The screen saver module, plus a copy of the video you chose for it | Screen saver |

### The lock-screen video, in detail

1. StayLive copies your converted video next to Apple's Aerials, under its own id, with the download attributes macOS checks (`SourceURL`, `LastETag`) plus one of its own (`StayLive.wallpaperID`), so it can tell its own files apart from Apple's. Apple's video files are not touched.
2. It writes its own catalog (Apple's list plus a **StayLive** category) and sets the two preferences that make macOS load it. Apple's `entries.json` is never modified.
3. It selects your video as the wallpaper in `Index.plist`, remembering which Apple Aerial you had.
4. It restarts `WallpaperAgent`, the per-user process that draws wallpapers, so the change shows up. macOS relaunches it immediately.

**Fallback:** if macOS doesn't load StayLive's catalog, StayLive undoes steps 1–3 and instead replaces the Apple Aerial you selected, after copying Apple's original to `~/Library/Application Support/StayLive/Backups/<id>.mov` (never overwritten).

**Undo:** StayLive → Settings → Lock Screen → **Stop Using StayLive Aerials** removes the two preferences, StayLive's catalog, videos and thumbnails, re-selects your previous Apple Aerial and restores any backed-up original.
To do it by hand:

```bash
defaults delete com.apple.wallpaper.aerial AerialManifestForceLocal
defaults delete com.apple.wallpaper.aerial AerialManifestLocalPathOverride
killall WallpaperAgent
```

then pick an Aerial in System Settings → Wallpaper.

## Processes it runs

| Command | When | Why |
|---|---|---|
| `/usr/bin/killall WallpaperAgent` | After installing or removing a lock-screen video | Makes macOS reload the Aerial (your user's own process; it restarts automatically) |
| `/usr/bin/log show` | Right after installing a lock-screen video | Reads the Aerial extension's log line confirming it loaded StayLive's catalog (read only) |
| `/usr/bin/codesign --sign -` | After updating the screen saver's video | Re-signs the screen saver bundle locally (ad-hoc), because its contents changed |

## Screen saver behavior

macOS runs third-party screen savers in a sandboxed helper (`legacyScreenSaver`). StayLive's screen saver:

- only reads files inside its own bundle;
- plays sound only after macOS announces that a screen saver has actually started, and only on your main display;
- fades out and stops when macOS announces that the screen saver is ending, when your displays go to sleep, or when its view is removed.

## Removing StayLive completely

1. In StayLive → Settings → Lock Screen, click **Stop Using StayLive Aerials** (if you used the lock screen).
2. In System Settings → Screen Saver, pick another screen saver.
3. Turn off **Launch at login**, quit StayLive (menu bar → power icon) and delete `StayLive.app`.
4. Delete these if you want to remove your library and settings too:
   - `~/Library/Application Support/StayLive/`
   - `~/Library/Screen Savers/StayLive.saver`
   - `~/Library/Preferences/<bundle id>.plist`

## Reporting a problem

Please open an issue. For anything security-related, describe the issue without posting exploit details publicly, and it will be handled privately first.
