# Arduino button -> visitor station

## How it fits together

    [button] -> [Arduino] --USB--> PC (COM port) -> visitor-station.ps1 -> intro video on the screen
                                   PC <--USB-- [headset]   (mirror, status, app start)

The Arduino never talks to the headset. On press it prints `START` over its USB serial connection; the PC
sees the Arduino as a COM port, and the station reads the text from that port.

## 1. Put the sketch on the Arduino (once)

1. Install the Arduino IDE (arduino.cc/en/software).
2. Open `moi_button/moi_button.ino`, pick your board (Tools -> Board) and port (Tools -> Port), click Upload.
3. Wiring: button between **pin 2** and **GND**. A sensor with a digital output: output to pin 2, and if it
   goes HIGH when triggered set `ACTIVE_LOW = false` at the top of the sketch.

Check it: Tools -> Serial Monitor, 9600 baud, press the button -> `START` appears. Hold 5 s -> `RESET`.
**Close the Serial Monitor afterwards** - a COM port can only be open in one program at a time.

## 2. Run the station

    powershell -ExecutionPolicy Bypass -File Deploy\visitor-station.ps1 -ListPorts
    powershell -ExecutionPolicy Bypass -File Deploy\visitor-station.ps1 -Windowed

`-ListPorts` shows the COM ports and which one the station would pick. Arduino boards (genuine, CH340,
CP210x, FTDI) are found automatically; otherwise pass `-SerialPort COM5`. When the button is pressed the
station log shows `button connected on COM5` once, then `serial: START` and the intro starts.

The station accepts `START` with or without a line ending, case-insensitive. A line containing `RESET` sends
it back to the waiting screen. Different text or speed: `-SerialCommand GO -BaudRate 115200`.

## Testing without the Arduino: Hercules + a virtual COM port pair

A virtual serial port driver (com0com, VSPE, Virtual Serial Port Driver) creates a *pair* of ports that are
wired to each other, e.g. COM10 <-> COM11. Whatever is written to one comes out of the other.

1. Create the pair (COM10 <-> COM11 in this example).
2. Hercules -> Serial tab -> Name COM10, Baud 9600 -> Open.
3. Station on the other end:
   `powershell -ExecutionPolicy Bypass -File Deploy\visitor-station.ps1 -Windowed -SerialPort COM11`
4. In Hercules type `START` in a Send box and click Send -> the station logs `serial: START` and the intro plays.

Virtual ports are never auto-detected (the station can't know which end is yours), so `-SerialPort` is required.

## Using Hercules with the real Arduino

Hercules can replace the Arduino Serial Monitor to watch what the Arduino sends (Serial tab, the Arduino's
COM port, 9600). But **close the port in Hercules before starting the station**, or the station reports
"port is busy".

## The museum's button board (tested 2026-09-27)

The board supplied is an **Arduino Mega 2560 (COM8 here, USB VID 2341 / PID 0042)** that already has its own
firmware - do **not** upload `moi_button.ino` to it, that would erase it.

What it sends (9600 baud):
- `PUSH_TO_PLAY` - from the play button, **and** every time the board restarts (RESET button, or the PC
  opening the port). The station starts the intro on it, and ignores anything in the first 3 s after connecting.
- `*OK#` - after a press and from some of the other buttons. Ignored by the station.
- Of the 5 buttons, only one sends `PUSH_TO_PLAY`; the others send `*OK#` or nothing.

For a staff reset button, ask the firmware's author to make a spare button send `RESET`.
