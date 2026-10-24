# How StayLive works

StayLive has three independent parts: the desktop, the lock screen and the screen saver.
All three are fed from the same library of videos.

## Desktop

For every display, StayLive creates a borderless window at the macOS *desktop window level*. That puts it
above the wallpaper but below the Finder's desktop icons. The window ignores the mouse, appears on every
Space and plays the video with `AVPlayerLooper`.

To save power, playback pauses when:

- the window is fully covered (`NSWindow.occlusionState`);
- the screen is locked (`com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`);
- the displays are asleep;
- you're on battery and enabled *Pause on battery*;
- you press pause.

Sound, when enabled, plays from the main display's window only.

## Lock screen

### The idea

When an **Aerial** is your wallpaper, the lock screen plays it from a video file that macOS downloaded into
`~/Library/Application Support/com.apple.wallpaper/aerials/videos/<asset id>.mov`.
Which Aerials exist is described by a catalog, `aerials/manifest/entries.json`: categories, names,
thumbnails and, for each asset, the URL its video came from.

macOS's Aerial extension reads two preferences in the `com.apple.wallpaper.aerial` domain:

| Key | Effect |
|---|---|
| `AerialManifestForceLocal` (bool) | Skip the downloaded catalog |
| `AerialManifestLocalPathOverride` (path) | Load this catalog file instead |

StayLive writes its own catalog, `aerials/manifest/staylive-entries.json`: Apple's current list plus a
**StayLive** category holding one asset per converted video, and points those two preferences at it.
Your videos then show up in System Settings → Wallpaper like any other Aerial, and the lock screen plays
them with the smooth slow-down when you unlock.

Three details make this work:

1. **Keep the download attributes.** macOS tags each Aerial file with `SourceURL` and `LastETag` extended
   attributes, and only uses a file whose `SourceURL` matches the catalog's URL for that asset. Otherwise it
   assumes the file is stale and tries to download it. StayLive gives each of its assets a
   `https://staylive.local/…` URL and sets matching attributes on the file, so nothing is ever downloaded.
2. **Match the format exactly.** The Aerial player only plays files that look like Apple's.
3. **Follow Apple's list.** When macOS downloads a newer `entries.json`, StayLive rebuilds its catalog from
   it, so Apple's new Aerials keep appearing.

### The format Apple's player expects

Observed from Apple's own Aerial files and from how the player behaves:

| Property | Value |
|---|---|
| Codec | HEVC (H.265) Main10, 10-bit 4:2:0 |
| Size | 3840 × 2160 |
| Frame rate | 240 fps, timescale 240000 |
| GOP | closed |
| Temporal layers | each frame is tagged with a temporal level; levels ≥ 1 are switch points (TSA) |

**Why 240 fps and temporal levels?** The unlock slow-down plays the video at a decreasing rate.
For normal playback the player decodes only the low temporal levels (about 30 fps of frames). While it
slows down, it switches up to higher levels, one at a time, so the slow motion still has enough frames to
look smooth. It only switches at frames marked as *temporal sub-layer access* (TSA) points.
Every frame must carry its temporal level: when the player searches the file for a frame to start or stop on,
a frame without one makes it fail with an error.

### The conversion

`AerialEncoder` (in `App/LockScreen.swift`) turns any video into that format:

1. Read the source frames with `AVAssetReader`.
2. Scale each frame to 3840 × 2160 with `VTPixelTransferSession`, letterboxing if the aspect ratio differs.
3. Repeat each frame to reach 240 fps (a 24 fps clip shows each frame 10 times; a 60 fps clip 4 times).
4. Loop the clip until it's at least 60 seconds long, in whole loops (at most 180 s).
5. Encode with the hardware HEVC encoder (`VTCompressionSession`): Main10, closed GOP,
   4 temporal layers (30 / 60 / 120 / 240 fps).
6. Mark every frame at level ≥ 1 as a TSA point, then write the file with `AVAssetWriter`.
7. Check that every frame was written (the conversion fails rather than install a damaged file).

The Mac is kept awake during a conversion, which is usually about 4–5 minutes per minute of output on
Apple silicon. Converted files are cached, so applying a video a second time is instant.

### Installation

`AerialCatalog.sync` (in `App/AerialCatalog.swift`) copies each converted video to
`aerials/videos/<wallpaper id>.mov` (an APFS clone, so it takes no extra space), sets the attributes,
writes a thumbnail and the catalog, and sets the two preferences. `AerialCatalog.select` then makes the
chosen asset your wallpaper by updating the Aerial choice in `Store/Index.plist`, the same file System
Settings writes, and `WallpaperAgent` is restarted so it reloads.

StayLive then checks the system log for the Aerial extension confirming it loaded StayLive's catalog.
If it didn't, StayLive turns the catalog off again and falls back to the older method: back up Apple's
selected Aerial video once, copy the converted video into its place with the same attributes, and restart
`WallpaperAgent`.

Removing a video from the library removes its Aerial. **Stop Using StayLive Aerials** deletes the two
preferences, StayLive's catalog, videos and thumbnails, re-selects the Apple Aerial you had before, and
restores any Apple video replaced by the fallback.
Conversions run in a queue; only your most recent lock-screen choice gets installed.

## Screen saver

`StayLive.saver` is a regular `ScreenSaverView` module. macOS runs third-party screen savers inside a
sandboxed helper process, which can read only the saver's own bundle. So when you choose a screen-saver
video, the app copies the video and a small `settings.plist` into the installed bundle and re-signs it.

### Sound rules

macOS can start, restart or keep a screen-saver view around in situations where no screen saver is
actually showing (for example while the display wakes at the lock screen). To make sure sound never
plays in the background, the screen saver:

- plays sound only after macOS posts `com.apple.screensaver.didstart`;
- plays from one view only, on the main display, using a file lock shared by all screen-saver processes;
- ignores starts that arrive after macOS posted `com.apple.screensaver.willstop`;
- stops a start that was never confirmed if the screen stays unlocked for 5 seconds;
- fades out within about 0.3 s on `willstop` / `didstop`, display sleep, `stopAnimation` or removal from its window.

## Code map

| File | Responsibility |
|---|---|
| `App/StayLiveApp.swift` | App entry point, window, menu bar extra and settings scenes |
| `App/Library.swift` | Video library: import, metadata, thumbnails, storage |
| `App/DesktopController.swift` | Desktop windows, playback rules, sound, launch at login |
| `App/LockScreen.swift` | Lock-screen encoder, conversion queue, install and restore |
| `App/AerialCatalog.swift` | StayLive's Aerial catalog, preferences and wallpaper selection |
| `App/ScreenSaver.swift` | Installs and updates `StayLive.saver` |
| `App/Views.swift` | SwiftUI interface |
| `App/Theme.swift` | Colors, backgrounds and button styles |
| `ScreenSaver/StayLiveSaverView.swift` | The screen saver itself |
