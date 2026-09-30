# Deploying MOI "The Promise of Safety" to several VIVE Focus Vision headsets

## 0. New PC checklist (do these in order)

1. **Copy the project folder** (`VR`) to the PC. Only `Deploy\` is needed to run the station.
2. **Install scrcpy:** `winget install Genymobile.scrcpy`
3. **Screen:** plug in the VR screen (landscape or portrait - both work) and set its resolution in Windows
   Settings -> Display (and Portrait if it is turned on its side). On a laptop: "Extend these displays".
   The station puts itself on the screen attached to the PC automatically - never on a laptop's own panel
   unless nothing else is connected - and moves there if the screen is switched on after the PC. Check with:
   `powershell -ExecutionPolicy Bypass -File Deploy\visitor-station.ps1 -IdentifyScreens`
   Screens are numbered left to right as arranged in Windows Display settings, not by cable or port.
4. **Headset:** USB debugging on, plug the cable in, accept "Allow USB debugging" with "Always allow" ticked.
5. **Button box:** plug it in and check it is found:
   `powershell -ExecutionPolicy Bypass -File Deploy\visitor-station.ps1 -ListPorts`
   The COM number does not matter; the Arduino is recognised by its USB ID. Close Hercules / the Arduino
   Serial Monitor first - only one program can use the port.
6. **Test in a window:** `... visitor-station.ps1 -Windowed` and do a full visit.
7. **Install icons and autostart** with the same options (whatever you add is baked in):
   `... visitor-station.ps1 -InstallShortcuts` and `... visitor-station.ps1 -InstallAutostart`
   (only add `-Screen N` to force a screen, N = 1 for the leftmost, if the automatic choice is ever wrong)
8. Windows: automatic sign-in, never sleep, display never off.
8b. Content icons: `powershell -ExecutionPolicy Bypass -File Deploy\update-content.ps1 -InstallShortcuts`
   ("Replace headset film", "Replace intro video" - drag a video onto them).
9. If anything misbehaves, read `Deploy\logs\station-<date>.log`.

### Changing the content
- The two desktop icons: double-click and choose the file in the picker, or drag the file onto the icon. The
  window stays open with the result (Enter, or 20 s), then the station is started again - also if staff had
  closed it (Ctrl+Shift+Q) to reach the icon. Errors are shown in that window, never a flash.
- **360 film (headset):** **Replace headset film**, or
  `Deploy\update-content.ps1 -Film "D:\new\film.mp4"` (add `-Layout TopBottom360` for a stereo film).
  It goes into the app's own folder as `journey.mp4`, is checked byte-for-byte, and the next visit plays it.
  Refused while a visitor is watching. Spec: MP4 H.265 (HEVC) **8-bit**, 30 fps, mono 360 up to 7680x3840;
  its centre is "straight ahead". The film in the package is the 8K 8-bit copy of the client's 10-bit master
  `AlFakher_Mono360_8K.mp4` (zscale error-diffusion dither, hevc_qsv 55 Mbps, BT.709 tags). Measured on the
  Focus Vision FA66C3N00269 (2026-09-28, app frame-rate log): 8K 30.0 fps / 0 dropped, 5.7K and 4K the same;
  the 8K looked sharpest. The headset's screens show about 20 px per degree, 8K has 21 (4K only 11).
  **Since 2026-09-28 evening the film is the client's new `AlFakher_New.mp4`** (7680x3840 8-bit HEVC as delivered,
  30 fps, 140 s, ~100 Mbps, 1.66 GB, both streams start at 0) in both packages. 100 Mbps is untested on the
  headset (55 Mbps played at 30 fps); a 55 Mbps re-encode `AlFakher_New_55mbps.mp4` sits next to the zips in
  `Delivery` as the fallback if the app's frame-rate log shows dropped frames. The previous 68 s film is kept as
  `Delivery\previous-film-68s-8K.mp4`.
- **Intro (PC):** **Replace intro video**, or `-Intro "D:\new\intro.mp4"`. Replaces
  `Deploy\intro.mp4` (old one kept as `intro_previous.mp4`); the station is stopped and restarted around the
  copy with the same options. Spec: MP4 H.264 with sound, same shape as the screen: landscape 3840x2160 (or
  1920x1080), portrait 2160x3840.
- Only the PC connected to the headset can replace the film; it needs the headset switched on and on its cable.

### Lessons from the first install (already fixed in the script)
- **Mirror invisible although running:** it was launched with a "hidden" window flag. It is now launched
  without a console but with its window shown, and brought to the front when the mirror step starts.
- **Mirror on the wrong screen:** with Windows display scaling (e.g. 150%) the station measured screens in
  scaled units while scrcpy used real pixels. The station now uses real pixels too. Both windows are locked
  full screen on purpose, so they can't be dragged. The station now picks the attached screen by itself
  (built-in laptop panels are recognised through Windows' monitor connection type) and re-checks every 3 s.
- **Intro picture stuck at the start while the sound played:** Windows' video player shows the first frame of a
  freshly opened video and then does not move it for several seconds (every video file, measured on screen); a
  second play of a loaded video is smooth. The station now opens the intro once, plays it silently for a moment
  under a black cover whenever "Press the button" is showing, and keeps it loaded, so every visitor gets the
  smooth second play. Because it stays open, **intro.mp4 cannot be copied over while the station runs** - use
  the "Replace intro video" icon, or close the station (Ctrl+Shift+Q) first.
- **Two stations at once** (icon clicked twice, or icon + autostart): now impossible, the second one exits.
- **Mirror not on the screen while a visitor was in the headset** (second PC, once; fine on the retry): after
  "Please put on the headset" the station used to switch to the mirror after 12 s even if nobody wore the
  headset yet, count the headset lying on the table as "taken off" and go back to "Press the button" 5 s later -
  so a visitor who needed more than ~17 s to put it on got no mirror. The headset's own screens when it is put
  on (lens/IPD adjustment, boundary) pause the app, and a pause also counted as "taken off"; and during the film
  the station gave up after 5 s off while the headset app only stops the film after about 10 s. Now: the
  station waits on "Please put on the headset" until the headset reports it is worn (2 min at most), a pause
  is not "off", during the film the station follows the headset app, and the mirror is put back on top of
  everything once a second (the station screen likewise while it is showing). Log lines to look for:
  `headset put on`, `mirror on screen`, `headset off for 8 s`, `film stopped by the headset (taken off)`,
  `... was covered by '<program>'`.
- **Ctrl+Shift+Q did not close the station** (zips of 2026-09-28 before 16:50): the close handler's parameter was
  `$s`, and PowerShell names ignore case, so it hid the station state `$S` and every close was refused as
  "Alt+F4". The same mistake in the intro-failed handler could leave a broken intro on a black screen. Both fixed
  (`$src`), and the intro now moves on to "Please put on the headset" if it hasn't started after 8 s (or runs
  10 s past its length). Never name a variable `$s` in visitor-station.ps1. The small test window (-Windowed)
  closes with its close button; full screen only with Ctrl+Shift+Q or the Stop icon.
- **A short tap of the button key (F9) was sometimes missed** (seen 2026-09-28 in the full test): the station
  read the key 20 times a second on its main thread, which is busy for a moment every second while it reads the
  headset over USB. The key and Ctrl+Shift+Q are now watched on a thread of their own; every press is logged
  (`button: key F9`). The Arduino was never affected (its messages are queued). Also: the calls that keep the
  mirror on top no longer wait for the mirror program, so a hung scrcpy can't freeze the station, and Alt+F4 no
  longer closes the station.

### Button box: different COM port or different message
- **COM port changes** (other PC, other USB socket): nothing to do. Auto-detect finds genuine Arduino (USB
  vendor 2341/2A03) and the usual clone chips (CH340 1A86, CP210x 10C4, FTDI 0403) whatever the COM number,
  and reconnects after unplugging. Only if the board uses another chip, or two such boards are plugged in,
  give the port explicitly: `-SerialPort COM5`.
- **The board sends a different message:** `-SerialCommand "NEWTEXT"` (several: `"PUSH_TO_PLAY,START,GO"`).
  Matching ignores upper/lower case, works with or without a line ending, and matches if the line contains
  the text. A line containing `RESET` always sends the station back to waiting. Different speed: `-BaudRate`.
- Whatever you change, re-run `-InstallShortcuts` and `-InstallAutostart` with the same options so the icons
  and the autostart use them too. To see exactly what the board sends: open its COM port in Hercules at the
  board's baud rate and press the button (then close Hercules again).

## 0b. What the visitor sees in the headset (since 2026-09-29)
- START screen: a looping 8K 360 video (`Al_Fakhr_Intro_360.mp4`, 8.2 s, with its sound), nothing else. The video is
  inside the app (`Assets/StreamingAssets/StartScreen360.mp4`, path in the sequence asset `startScreenVideoPath`;
  empty = the old museum room). Changing it needs a new build.
- START: the panel drawn in that video (straight ahead). The app's START button is an invisible hotspot over it
  (sequence asset `startHotspot`: yaw 0, pitch 1.85, 27 x 11 degrees, 8 m; width 0 = visible button instead). Only a
  controller starts it (point + trigger, or A/X); looking at it does nothing (`ExperienceHud.gazeStart` = false). A new
  START video with the panel elsewhere needs these numbers changed (measure the panel in a frame: yaw = (x/W - 0.5) *
  360, pitch = (0.5 - y/H) * 180).
- The film (`content/journey.mp4` = `Al_Fakhr_Final_Version_360.mp4`, 8K 8-bit HEVC, 140 s, 40 Mbps, 666 MB), then
  back to the START screen.
- Zoom during the film: zoomed OUT (the picture looks 1.25 times farther away): 1 until 35 s, eased to 0.8 by 36 s,
  held to the end; every start begins at 1. Defaults in the sequence asset (`filmZoom`); per film in `film.json` next
  to it: `{ "zoomAt": 35, "zoomOver": 1, "zoomTo": 0.8 }` (`"zoomTo": 1` = no zoom, below 1 = out, above 1 = in).
  The front of the picture is scaled, easing back to 1 behind the visitor (shader `MOI/Panorama360`), so the whole
  sphere stays covered.
- Button box texts: `button-commands.txt` next to `visitor-station.ps1` (`command = PUSH_TO_PLAY, START` - texts separated by commas - `port = auto` or `COM5`, `baud = 9600`; older one-text-per-line files still work);
  command-line options win. `-ListPorts` prints what the station will use.

- Mirror slice centre (2026-09-30): straight ahead in the left-eye image is at 1414 of 2448 px (57.8%, lens towards the
  nose; measured on FA66C3N00269 with both eyes so a head turn cancels out). The slice is centred there (`-MirrorCentre 0.578`),
  2048 px wide max (1920x1080: 2048:1152:390:648; 3096x1290: 2048:856:390:796). Before, it was centred on 1224 and the
  mirror looked turned to the side.

## 1. One-time setup per headset (5 min each)
1. Power on, finish HTC setup (Wi-Fi = the museum LAN, pair controllers, set boundary / stationary mode).
2. Settings -> Advanced -> Developer options -> **USB debugging ON**
   (if Developer options is missing: Settings -> About -> tap Build number 7 times).
3. Plug into the PC (the single USB-C port on the headset), put it on, accept **Allow USB debugging**,
   tick *Always allow from this computer*.
4. Give it a name/label with its serial (`adb devices` shows it, e.g. `FA66G3N00188`).

## 2. Install on all headsets at once
Plug in every headset (USB hub is fine) and run from the project folder:

    powershell -ExecutionPolicy Bypass -File Deploy\deploy-headsets.ps1 -Launch

Options:
- `-Film "D:\film\journey.mp4"` copies the film onto every headset, into the app's own folder
  (`Android/data/com.gamex.moi.promiseofsafety/files/journey.mp4`). Add `-Layout TopBottom360` if the film is
  stereo top-bottom (default is mono 360). The app also accepts a film at `/sdcard/MOI/journey.mp4`.
  Uninstalling the app deletes the copy in its folder; updating with this script keeps it.
- `-ManifestUrl "http://<server-ip>:8765/manifest.json"` points every headset at the LAN content server,
  so later film updates reach all headsets automatically (no cable needed after this).

The script installs/updates the APK (keeps settings), grants permissions, sets "stay awake while charging",
and optionally launches the app. Re-run it any time you rebuild the APK.

## 3a. Single headset with button + intro video (current setup)

One PC, one headset on a USB cable, one screen, one physical button. `visitor-station.ps1` runs the sequence:

1. Screen: "Press the button to begin".
2. Button pressed: the intro video plays full screen on the PC, with sound.
3. Screen: "Please put on the headset".
4. As soon as the headset is worn (or START is pressed in it), the screen switches to the live mirror of the
   headset. Nobody puts it on within 2 minutes (`-WearGiveUp 120`): back to step 1.
5. When the film in the headset ends, back to step 1.
The headset decides as well (defaults since 2026-09-28): put on at ANY time - at step 1 or during the intro -
the mirror comes at once (the intro stops); taken off for 5 s (`-OffReset 5`), film or not, back to step 1 and
the app is told to go back to START (command file, see 3d). `-WaitForButton` / `-KeepFilmWhenOff` give the
older behaviour (view only after the intro; the headset app ends the film itself ~10 s after removal) - advanced
options only: since 2026-09-29 the PC demo has one start file, `START PC DEMO.bat` (the "button first" file is gone).
PC demo (`-PcApp`): **"worn" comes from the headset's own proximity sensor, read over USB with adb** (since
2026-09-30). `MoiProximityPoller` (C# thread in `visitor-station.ps1`) runs `adb -s <serial> shell dumpsys
sensorservice` once a second (~40 ms) on the VIVE headset among the adb devices and takes the newest event of
"ucs148c1 Proximity Sensor Wakeup: last 30 events" (`N (ts=..., wall=...) V, 0.00, 0.00`, V 0.00 = near = worn,
1.00 = far = off; newest by `ts`, because the headset's wall clock is wrong without internet). A reading older than
3 s counts as none. Station log: `headset proximity sensor: worn / taken off`, `...: read over USB (<serial>)`,
`...: no reading (<why>)`. While there is a reading it alone decides; `-NoProximity` switches it off. A film that
starts in Waiting / Intro / Wear while the sensor says "off" is not a visitor (an app that starts on a look, set off
by a headset standing on a table) - the station resets the app and stays on "Press the button".
Why: the two older signals, now only the fallback, both stay "worn" until the headset falls asleep, 3 minutes after
it is put down (the Focus Vision's shortest sleep setting) - measured on the ASUS PC 2026-09-30: worn=True from app
start with the headset on the table, SteamVR Ready throughout, no reset in 60 s; with the sensor: on -> view in the
same second, off -> "Press the button" + app reset after exactly 5 s (3 films), on during the intro -> intro stops.
Requirements it adds: USB debugging on the headset and this PC allowed once ("Allow USB debugging?", "Always allow");
kiosk mode off or allowing VIVE Streaming (as before). adb: the station uses the exe of the adb server that is already
running, else VIVE Hub's `VIVE Hub\CommonTools\ADB\adb.exe` (installed on every PC-demo PC), else the scrcpy/Unity
copy, else PATH. VIVE Hub 30.0.4, Unity 34.0.5 and scrcpy 37.0.0 adb all speak protocol 41, so none of them restarts
another's server; the poller starts the server with a 30 s limit (as `MoiHeadsetPoller`).
Fallback signals: the app's wear sensor (OpenXR user presence) and SteamVR's own state from
`<Steam>\logs\vrmonitor.txt` (`Transition ... to 'SteamVRSystemState_Ready'` /
`'..._Standby'`; Steam folder from `HKCU\Software\Valve\Steam\SteamPath`). SteamVR decides when the app reports
`worn=Unknown`; a Standby later than the app's last "worn" always counts as off (sensor missing or stuck); SteamVR's
Ready alone never overrides the app's "not worn" (staff picking the headset up). `-NoSteamVr` switches it off,
`-SteamVrLog <file>` reads another file (tests: `Deploy/dev-tools/steamvr_signal_test.ps1`, 42 checks incl. the proximity sensor and its parser).

**The button (Arduino over USB serial).** Sketch: `Deploy/arduino/moi_button/moi_button.ino`.
Button (or a sensor's digital output) between pin 2 and GND; upload with the Arduino IDE; plug the Arduino
into the PC by USB. On press it sends `START`; holding 5 s sends `RESET` (back to the waiting screen).
The station finds the Arduino's COM port by itself (Arduino, CH340, CP210x, FTDI boards) and reconnects if
it is unplugged. Options: `-SerialPort COM5` (fixed port), `-BaudRate 9600`, `-SerialCommand START`
(if your sketch sends different text). A USB keyboard button sending F9 still works as a backup (`-TriggerKey`).

**Setup**
- `winget install Genymobile.scrcpy`
- Put the intro video at `Deploy\intro.mp4` (or pass `-Intro "D:\path\intro.mp4"`). Any MP4 (H.264) plays.
  Currently a placeholder: the 82 s headset recording of our app from 2026-09-25. Replace with the real intro.
- Headset: USB debugging on, cable plugged in, "Always allow" accepted, our app running.
- Test: `powershell -ExecutionPolicy Bypass -File Deploy\visitor-station.ps1 -Windowed`
- Real: `powershell -ExecutionPolicy Bypass -File Deploy\visitor-station.ps1 -TriggerKey F9`
- Start at logon: add `-InstallAutostart` to the real command once.

The mirror shows a 16:9 slice through the middle of the headset's left eye, so it fills a TV (the headset
renders both eyes side by side; the station detects this). `-Square` shows the whole eye with side bars.

Other options: `-Screen 2` (which screen), `-WearGiveUp`, `-OffReset`, `-Crop w:h:x:y` (manual crop),
`-MirrorAudio` (headset sound on the PC speakers), `-WaitingText` / `-WearText`. Staff quit: Ctrl+Shift+Q
(Alt+F4 is ignored on purpose, so a stray keyboard can't close the kiosk).

The headset app must be the build that writes its status file (2026-09-26 or later). With an older build, or
while the headset is not connected, the station still works but only on timers (`-WearTimeout 12` s to the
mirror / "Connecting to the headset...", 7 min back to waiting).

## 3c. Site screen: any shape (museum: one 3096 x 1290 screen on a desktop PC)

The station detects the screen's shape and cuts the mirror to it, so the mirror always fills the screen. The
slice stays inside the lens-shaped headset image (no black corners): landscape at most 2224 x 1248 of the
2448 px eye, portrait at most 1056 x 1872. Check any size with `visitor-station.ps1 -MirrorCropFor WxH`.
- **3096 x 1290 (2.4 : 1):** slice 2224 x 928 through the middle of the view, streamed at full size (2224 px,
  about 2 megapixels - same headset load as a full-HD stream). Verified: the headset encodes it.
- **16:9:** 2224 x 1248 (1280 px stream up to full-HD screens, 1920 px on 4K). **Portrait 9:16:** 1056 x 1872.
- **Intro:** make it at the screen's resolution (museum: 3096 x 1290). Another shape plays whole with bars;
  `-IntroFill` crops it to fill the screen instead (add it to `-InstallShortcuts` / `-InstallAutostart`).

Portrait details (4K 2160x3840):


- Windows: Settings -> Display -> select the TV -> Display orientation: **Portrait**, resolution **3840 x 2160**
  (shown as 2160 x 3840 once rotated). The station sees a screen taller than wide and switches to its portrait
  layout by itself (or force it with `-Portrait`).
- **Intro video: 2160 x 3840 (9:16 portrait)**, MP4 H.264 or H.265. A landscape video on a portrait screen
  plays with big black bars above and below (the current placeholder does exactly that).
- **Mirror:** a 9:16 slice from the middle of the headset view, `1056:1872:752:324` on the Focus Vision,
  streamed at full size (1056 x 1872). That is the most detail one eye of the headset gives in portrait, so on a
  4K screen it is scaled up about 2x: clear, but softer than the intro. Streaming at this size makes the headset
  work a little harder - keep an eye on its temperature on long days.

## 3b. Later: several headsets, each on its own screen

**Hardware**
- One Windows PC with a video output per screen (a GPU with 4 HDMI/DisplayPort outputs, or two small PCs
  with two screens each). scrcpy is light; the PC does not need to be powerful.
- One screen per headset, placed next to its headset position.
- One USB-C **data** cable per headset from the PC, 3-5 m (use an *active* USB-C cable above 3 m), routed from
  above or behind the visitor so nobody trips. The cable also keeps the headset charged all day.
- A powered USB hub if the PC lacks enough ports.

**PC preparation (once, done by you in Windows settings)**
- Windows: sign in automatically at boot (netplwiz / Settings -> Accounts), never sleep, never turn off
  displays, screen saver off, Windows Update active hours set outside opening hours.
- Set the screens to "Extend these displays" and arrange them left-to-right in Settings -> Display.
- Install scrcpy: `winget install Genymobile.scrcpy`

**Station setup (once, all headsets plugged in and USB debugging allowed on each)**

    powershell -ExecutionPolicy Bypass -File Deploy\mirror-station.ps1 -Setup

A big number appears on every screen; the headsets are assigned to screens 1, 2, 3... and saved in
`Deploy\mirror-config.json`. To swap which headset goes to which screen, edit the `screen` numbers there.
Label each headset with its name and serial.

    powershell -ExecutionPolicy Bypass -File Deploy\mirror-station.ps1 -DryRun           (check the plan)
    powershell -ExecutionPolicy Bypass -File Deploy\mirror-station.ps1 -InstallAutostart (start at logon)

**Daily operation**
Switch on the screens and the PC, then the headsets. Each screen shows "Headset N - waiting" until its
headset is connected, then its live view, full screen. Unplug / replug / headset restart are picked up
automatically within a few seconds. Staff never touch the PC. Ctrl+Q on a waiting screen quits the station.

**Notes**
- The view is mirror-only: nothing at the PC can press anything in the headset.
- The mirror is cropped automatically to a 16:9 slice of the left eye (Focus Vision: `2224:1248:110:600`).
  Set `"crop"` in `mirror-config.json` to override, e.g. `"2448:2448:0:0"` for the whole square eye.
- Don't run `deploy-headsets.ps1` while the station is running: the two use different adb versions and
  briefly restart each other. The station reconnects on its own afterwards, but screens flicker.
- `mirror-headsets.ps1` is a simpler manual version (one window per headset, no screen mapping).

**No-PC alternative: TV casting.** If the headset's quick menu (VIVE button) shows **Cast**, it can mirror over
Wi-Fi to a Miracast TV/dongle. It must be re-cast from inside the headset after every restart or Wi-Fi drop,
and its availability on our firmware is not verified. Not recommended for all-day operation.

## 3d. PC VR demo (the app runs on a PC and is streamed to the headset)

Package: `Delivery/MOI_PC_Demo/` (+ `.zip`, 901 MB): `MOI_PromiseOfSafety/` (Windows build + `content/journey.mp4`),
`START PC DEMO.bat` (checks the PC, then starts the app full screen), `README-PC-DEMO.txt` (setup for staff).
Sources: `Deploy/pc-demo/`. Build: **MOI > 4. Build Windows** (or `Temp/moi-command.txt` = `build-windows`, or
batch `-buildTarget Win64 -executeMethod MOI.EditorTools.MoiBuild.BuildWindows`) -> `Builds/Windows/`.
- The PC's OpenXR runtime carries it to the headset: VIVE Hub (VIVE Streaming) or SteamVR, set as "OpenXR
  runtime". The app window on the PC shows the headset view. Space on the PC keyboard = START.
- **Same visitor flow as the museum** (button -> intro -> "Please put on the headset" -> headset view -> back):
  START PC DEMO runs `visitor-station.ps1 -PcApp "MOI_PromiseOfSafety\MOI_PromiseOfSafety.exe"` (another film:
  `-PcFilm <path>`). In PC mode the station starts the app as a borderless window the size of the VR
  screen (`-popupwindow -screen-width/-height`, then placed and checked every second), takes over a running one,
  restarts it if it closes, reads its status file in LocalLow instead of over adb, and uses the app's window as
  the mirror (same keep-on-top logic as scrcpy). worn=Unknown counts as "no signal" there (a PC runtime may not
  report wearing): the mirror comes after WearTimeout. Ctrl+Shift+Q / `-Stop` also close the app. `-AppOnly` on
  the launcher = the app alone.
- **Headset decides the flow (user, 2026-09-28 evening; the default for both setups since the same evening):**
  a fresh worn=True reading in Waiting or Intro goes straight to Mirror (Intro is stopped via the Wear step); a
  visitor still wearing the headset after the film goes back into the view. worn=False for OffReset (5) s, film
  or not -> Waiting and `Send-AppCommand reset`: the station writes one word to `command.txt` in the app's own
  folder (adb `echo`+`mv` on the headset, temp+rename in LocalLow on the PC); the app polls it every 0.5 s and
  calls `ResetToStart` (`reload` reloads the scene). `-OffRestartsApp` (PC) restarts the process instead. On the
  headset the reads now run on a background thread (`MoiHeadsetPoller`: `adb devices` + guarded `cat` once a
  second, 5 s time limit per call), so the headset is watched during the intro too without the video stuttering;
  the app start check, the button-box search and a mirror (re)start still wait for the intro to end. Verified
  live on FA66C3N00269 (18:31-18:34): on -> view 0.1 s, off -> 5 s -> reset received, on during the intro -> view. **Depends on SteamVR reporting user presence** (XR_EXT_user_presence,
  OpenXR plugin 1.14): on Windows the app only reports worn/not worn when that extension is enabled and logs
  `[MOI] VR runtime reports whether the headset is worn` / `does NOT report`; without it worn=Unknown and the
  station falls back to the timers (12 s to the mirror, visit ends with the film). Not testable on the dev laptop
  (no runtime); `scratchpad/pc_wear_test.ps1` drives the status file instead.
- **PC demo verified end to end on the dev laptop (2026-09-28 19:09, SteamVR 2.x + VIVE Hub / VIVE Business
  Streaming over USB, Focus Vision FA66C3N00269):** SteamVR does report user presence (the app logs "VR runtime
  reports whether the headset is worn"; WORN True/False coincide with the OpenXR session going FOCUSED /
  SYNCHRONIZED). Put on -> view 0.1 s; off -> 5 s -> reset received by the app; on again -> view. While the
  headset lies on the table SteamVR keeps the session SYNCHRONIZED (standby): the app is running but not shown.
  **Crashes on this laptop:** 4 today, 3 in `vrclient_x64.dll` (SteamVR's client library, 0xc0000005) around
  standby/wake changes, 1 in `ViveOpenXRHandTracking.dll` at start-up 9 s after such a crash - the Intel Iris Xe
  isn't a supported VR GPU. The station restarts the app (now: logs the exit code, waits 5 s first). Watch for
  `VR app closed (exit code ...)` lines on the RTX PC; a few per day would be tolerable, many means SteamVR /
  driver trouble there too.
- **RTX 5080 PC, first run (2026-09-28 19:34 / 19:49, logs from the user):** button box on COM3 works, the 8K film
  plays at 30 fps / 0 dropped, SteamVR 2.17.10 with `XR_EXT_user_presence` enabled - but the app never logged
  `WORN`, so the station stayed on timers. Its OpenXR report shows `System Properties: Name="Vive OpenXR: Vive
  SRanipal"`, `OrientationTracking=False, PositionTracking=False`: one of VIVE Hub's implicit OpenXR API layers
  (`XR_APILAYER_VIVE_facial_tracking`, VIVE Business Streaming\OpenXR\ViveVR_openxr) stood in for the headset.
  **Real cause (RTX run of 19:58, layers still on, mirror worked):** the app only learnt the wear state from
  the Input System control, which changes on events - and when the headset is already active at app start
  (session FOCUSED from the first frame, as at 19:49), the first presence event arrives before the control
  exists and no further change comes. When the headset was idle at start and put on later (19:58), the change
  came through and `WORN True` appeared. Fix: on Windows `Worn` now asks the runtime directly each frame
  (`OpenXRUtility.IsUserPresent`, polled), still only when `XR_EXT_user_presence` is enabled; Android keeps the
  control. Kept as well: the station launches the PC app with VIVE Hub's four add-on layers off
  (`DISABLE_XR_APILAYER_VIVE_{HAND_TRACKING,FACIAL_TRACKING,MR,XRTRACKER}_1=1`; `-KeepViveLayers` keeps them) -
  harmless, the app uses none - and START pressed in the headset while the station is in Waiting/Intro goes to
  Mirror. Check on the RTX PC: start the demo with the headset already on -> `[MOI] WORN True` within a second.
- The final station accepts unknown parameters silently under `powershell -File` (an old launcher passing
  `-MirrorWhenWorn -OffEndsVisit` still ran), so a stale launcher doesn't stop the station - but keep the two
  in step anyway; the zip of 19:15 has the matching launcher (`-Yes` skips the "Start anyway?" prompt).
- Without a VR runtime the app ran uncapped and took 99% of the GPU, which starved the station (it froze once).
  `PcVrRuntime` (Windows player only): no runtime at start -> 60 fps cap and a retry of the XR loader every 10 s;
  when it succeeds it goes into VR and recenters. Measured here: 39% GPU; full visit passes 17/17
  (`scratchpad/pc_station_test.ps1`). The late-VR path itself is untested (no runtime on the dev laptop).
- Needs a gaming GPU and Microsoft's HEVC Video Extensions. DirectX 11 on purpose: on DirectX 12 the video
  player's decoder device failed and 4K HEVC fell back to the CPU.
- Film (history; now `AlFakher_New.mp4`, see 3a): `content/journey.mp4` was 7680x3840 **8-bit** HEVC 55 Mbps, encoded from
  the client's 10-bit master `AlFakher_Mono360_8K.mp4` (TouchDesigner's ffmpeg: zscale error-diffusion dither,
  hevc_qsv, BT.709 tags). Measured on the dev laptop (Intel Iris Xe): 10-bit 8K master = stuck at 0 fps (40% CPU,
  software decode); 8-bit 8K = 30.0 fps, 0 dropped, 5% CPU. 8K only (user, 2026-09-28): the 4K stand-by
  launcher was removed; the headset package plays the same 8K file. The app logs the real frame rate
  every 5 s: `[MOI] Film 7680x3840 at 20 s: 30.0 fps, 0 frame(s) dropped`.
- Film order on Windows: `-film <path>` on the command line (relative to the .exe folder or absolute), then a
  content-server film (if a manifest URL is set in `moi-config.json`), then `content/journey.mp4` next to the
  .exe, then the app's LocalLow folder.
- **No stand-in film in the builds (user, 2026-09-28).** The 25 MB 2K test film (`MOI_TestJourney360.mp4`, kept in
  `Review\old`) is out of StreamingAssets and out of the sequence. Without a real film a headset or PC build stays
  at START: the title above the podium says "The film is missing on this device. Please call a member of
  staff." (headset and mirror), the small status line says how to fix it, and START does nothing (the real-time
  storyboard journey only runs in the editor). The app re-checks every 2 s, so a film copied on while it runs
  is picked up. Headset film order: the app folder (`files/journey.mp4`), then `/sdcard/MOI/journey.mp4`.
- Verified on the dev laptop without a VR runtime (plain window): room renders, START, film plays from
  `content/` with GPU decoding (9% CPU). Not yet run streamed to a headset (the laptop has no SteamVR/VIVE Hub).
- Headset in kiosk mode can't open VIVE Streaming: turn kiosk off for the demo or allow VIVE Streaming.

## 4. Kiosk settings to check on each headset
- Auto-launch the app / lock to it: HTC **Kiosk mode** (Settings -> Kiosk mode, or VIVE Business Device Management).
- Disable sleep while worn/idle, boundary prompts (use stationary boundary), system update prompts.
- Keep headsets on charge between visitors.

## 5. Staff controls in the app
- START: point + trigger, or look at it 2 s, or A/X.
- Hidden reset: hold left Menu (or both grips) 2 s -> back to START; 6 s -> full app reload.
