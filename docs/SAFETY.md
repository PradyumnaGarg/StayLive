# Safety and privacy

StayLive is designed to be easy to trust and easy to remove. This page lists everything it does to your Mac.

## What it never does

- It never asks for an administrator password and never runs anything as root.
- It never touches system files (`/System`, `/Library`) and works with System Integrity Protection fully on.
- It installs no kernel or system extensions, background daemons or login hooks (launch at login uses Apple's standard "Login Items" mechanism, and only if you turn it on).
- It makes **no network connections**: no analytics, no update checks, no uploads. Your videos never leave your Mac.
- It requests no privacy permissions (camera, microphone, screen recording, files outside the ones you pick).

## What it reads and writes

All paths are inside your own home folder.

| Path | What | Why |
|---|---|---|
| `~/Library/Application Support/StayLive/` | Your library (copies of imported videos, thumbnails, converted lock-screen videos, backups) and `library.json` | The app's own data |
| `~/Library/Preferences/<bundle id>.plist` | Settings (volume, pause on battery, current wallpaper…) | Standard app preferences |
| `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist` | **Read only**, to find which Aerial you selected | Lock screen |
| `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json` | **Read only**, to show the Aerial's name | Lock screen |
| `~/Library/Application Support/com.apple.wallpaper/aerials/videos/<id>.mov` | **Replaced** with your converted video, after backing up the original | Lock screen |
| `~/Library/Screen Savers/StayLive.saver` | The screen saver module, plus a copy of the video you chose for it | Screen saver |

### The lock-screen video, in detail

1. StayLive reads which Aerial you selected in System Settings.
2. The first time it replaces that Aerial, it copies Apple's original video to
   `~/Library/Application Support/StayLive/Backups/<id>.mov`. It never overwrites that backup.
3. It writes your converted video in its place. The new file keeps the two download attributes macOS uses to recognize the Aerial (`SourceURL`, `LastETag`), plus one of its own (`StayLive.wallpaperID`), so it can tell its own files apart from Apple's.
4. It restarts `WallpaperAgent`, the per-user process that draws wallpapers, so the change shows up. macOS relaunches it immediately.

**Restore:** StayLive → Settings → Lock Screen → **Restore Apple's Original** copies the backup back.
You can also let macOS re-download the Aerial: delete the file in `aerials/videos/` and select the Aerial again in System Settings.

## Processes it runs

| Command | When | Why |
|---|---|---|
| `/usr/bin/killall WallpaperAgent` | After installing or restoring a lock-screen video | Makes macOS reload the Aerial (your user's own process; it restarts automatically) |
| `/usr/bin/codesign --sign -` | After updating the screen saver's video | Re-signs the screen saver bundle locally (ad-hoc), because its contents changed |

## Screen saver behavior

macOS runs third-party screen savers in a sandboxed helper (`legacyScreenSaver`). StayLive's screen saver:

- only reads files inside its own bundle;
- plays sound only after macOS announces that a screen saver has actually started, and only on your main display;
- fades out and stops when macOS announces that the screen saver is ending, when your displays go to sleep, or when its view is removed.

## Removing StayLive completely

1. In StayLive → Settings → Lock Screen, click **Restore Apple's Original** (if you used the lock screen).
2. In System Settings → Screen Saver, pick another screen saver.
3. Turn off **Launch at login**, quit StayLive (menu bar → power icon) and delete `StayLive.app`.
4. Delete these if you want to remove your library and settings too:
   - `~/Library/Application Support/StayLive/`
   - `~/Library/Screen Savers/StayLive.saver`
   - `~/Library/Preferences/<bundle id>.plist`

## Reporting a problem

Please open an issue. For anything security-related, describe the issue without posting exploit details publicly, and it will be handled privately first.
