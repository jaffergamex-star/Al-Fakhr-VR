THE PROMISE OF SAFETY - PC VR DEMO
==================================
Staff handbook (setup, daily use, kiosk mode, fixes): open PC-DEMO-HANDBOOK.html in a browser.

The experience runs on this Windows PC and is streamed to the VIVE Focus Vision over a USB cable, like
a SteamVR game. The visitor flow is the same as at the museum:

  "Press the button to begin"  ->  the intro film plays on the screen  ->  "Please put on the headset"
  ->  the screen shows what the visitor sees in the headset  ->  the visitor presses START, the 360 film
  plays  ->  back to "Press the button to begin" for the next visitor.


WHAT YOU NEED
  - This PC: Windows 10/11 with a gaming graphics card (this demo's PC has an RTX 5080).
  - The VIVE Focus Vision and a USB-C data cable (the one that came with it, or any USB 3 data cable).
  - The button box (Arduino) on a USB port - optional: F9 on the keyboard does the same.


INSTALL ON THE PC (one time)
  1. NVIDIA graphics driver - the latest, from nvidia.com or the NVIDIA App.
  2. VIVE Hub - HTC's free PC software (vive.com). It contains VIVE Streaming, which sends the picture
     to the headset.
  3. Steam, then SteamVR from inside Steam (both free). SteamVR is what the demo app talks to.
  4. "HEVC Video Extensions" from the Microsoft Store - the films are HEVC; without it they stay black.
  5. This folder: before unzipping, right-click the zip > Properties > tick Unblock > OK. Unzip it
     somewhere simple, e.g. C:\MOI_PC_Demo, and keep everything together.
  6. Double-click START PC DEMO once: it checks the PC and lists anything missing. If it says "No VR
     runtime is set": SteamVR > Settings > OpenXR > "Set SteamVR as OpenXR runtime".
  If Windows says "Windows protected your PC" the first time: More info > Run anyway (the app is not
  signed).

  On the headset: turn kiosk mode off (kiosk mode blocks the VIVE Streaming app the demo needs).


EACH DAY
  1. Plug the USB-C cable into the headset and into a USB 3 / USB-C port on the back of the PC.
  2. Open VIVE Hub on the PC and choose the USB connection. In the headset accept the "connect to PC"
     prompt (or open VIVE Streaming from the Library). You see the SteamVR home in the headset.
     Start SteamVR on the PC if it did not start by itself.
  3. Double-click START PC DEMO. The screen shows "Press the button to begin"; the museum room with
     START is already in the headset. (If the headset is connected after this, the app goes into VR
     by itself within about 10 seconds.)
  4. Close the demo at the end of the day with Ctrl+Shift+Q (closes the station and the app).


DURING A VISIT
  - The visitor presses the button (or staff press F9): the intro plays, then the screen asks to put on
    the headset. As soon as the headset is on, the screen shows the headset view.
  - Putting the headset on at ANY time shows the headset view straight away - also while "Press the
    button to begin" is showing, or during the intro (the intro then stops). The button is optional.
  - START in the headset: point a controller at it and pull the trigger, or look at it for 2 seconds.
    (Space on the PC keyboard also presses START, while the headset view is showing.)
  - Taking the headset off, at START or during the film: after 5 seconds the screen goes back to
    "Press the button to begin" and the experience restarts, so the next visitor starts fresh.
    (Lifting it for a moment and putting it straight back on changes nothing.)
  - After the film the screen goes back to "Press the button to begin"; a visitor still wearing the
    headset stays in the headset view and can press START again.
  - Staff reset in the headset: hold the left controller's Menu button (or both grips) for 2 seconds =
    back to START, turned to face the visitor; 6 seconds = reload.


THE FILM: 8K
  The demo plays the film in 8K (MOI_PromiseOfSafety\content\journey.mp4: 7680x3840, 2 min 20 s), the
  same file as the museum headsets - the sharpest picture. It is the client's AlFakher_New.mp4 as
  delivered (8-bit HEVC). Windows and the headset play 8-bit 8K on their graphics chips; a 10-bit file
  freezes on the first frame, so replace it only with an 8-bit file.
  How smoothly it plays: the app's log (path below) writes a line every 5 seconds, e.g.
  "[MOI] Film 7680x3840 at 20 s: 30.0 fps, 0 frame(s) dropped". Dropped frames = the PC can't keep up.


CHANGING THE INTRO OR THE FILM
  Close the demo first (Ctrl+Shift+Q).
  - Intro: replace intro.mp4 in this folder (same name). Best made at the screen's resolution.
  - Film: replace MOI_PromiseOfSafety\content\journey.mp4 (same name, 8-bit). Optional film.json next to
    it, e.g. { "layout": "TopBottom360", "yaw": 0 } for a stereo top/bottom film.


OTHER WAYS TO START
  In a PowerShell window in this folder:
  .\start-pc-demo.ps1 -AppOnly      just the app, full screen, no button / intro (close with Alt+F4)
  .\start-pc-demo.ps1 -Check        only check the PC


IF SOMETHING DOES NOT WORK
  - Taking the headset off does nothing / putting it on does not start the view: the station follows two
    signals - the headset's wear sensor (through the app) and SteamVR's own state (Ready / Standby, from
    SteamVR's log vrmonitor.txt). The station log (logs folder) shows "SteamVR: Ready" / "SteamVR: Standby"
    and "headset: ... worn=True/False" lines; the app's log (path below) shows "[MOI] WORN True/False".
    If neither changes when the headset is put on and taken off, send both logs. (The demo switches VIVE
    Hub's OpenXR add-ons off for the app because one of them hid the sensor on a PC.) With no signal at all
    the demo still works with the button and the intro: the headset view comes 12 seconds after the intro
    or as soon as START is pressed in the headset, and a visit ends when the film ends.
  - The headset shows the SteamVR home but not the museum: SteamVR must be the OpenXR runtime (install
    step 6). The app looks for the headset every 10 seconds; if it still doesn't appear, close the demo
    (Ctrl+Shift+Q) and start it again with the headset connected.
  - The film stays black: install HEVC Video Extensions (Microsoft Store), and update the graphics driver.
  - The headset (and screen) say "The film is missing on this device": MOI_PromiseOfSafety\content\journey.mp4
    is gone. Copy it back from the zip; the message goes away by itself within a few seconds.
  - The picture in the headset stutters: check the cable is in a USB 3 port on the PC (not a hub), and
    lower the streaming quality in VIVE Hub.
  - The headset goes black for a few seconds and the room comes back: the experience closed (usually
    SteamVR's link crashing) and the station started it again by itself. The station log says
    "VR app closed (exit code ...)". Once in a while is harmless; often means a graphics-driver or SteamVR
    problem on that PC - update both.
  - The button does nothing: check the screen shows "Press the button to begin"; F9 works as a backup.
  - Logs: this folder's "logs" (the station) and
    %USERPROFILE%\AppData\LocalLow\GameX\MOI Promise of Safety\Player.log (the app).
