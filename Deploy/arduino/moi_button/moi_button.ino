// MOI visitor station button.
// Sends "START" over USB serial when the button is pressed (or the sensor triggers).
// Holding the button for 5 seconds sends "RESET" (staff: back to the waiting screen).
//
// Wiring: button between pin 2 and GND (no resistor needed, the internal pull-up is used).
// For a sensor with a digital output that goes LOW when triggered, wire its output to pin 2 instead.
// If your sensor goes HIGH when triggered, set ACTIVE_LOW to false.
//
// Board: any Arduino with USB (Uno, Nano, Leonardo, Pro Micro...). Upload with the Arduino IDE.
// The PC side (Deploy/visitor-station.ps1) finds the board's COM port by itself.

const int  BUTTON_PIN   = 2;
const bool ACTIVE_LOW   = true;     // button to GND with pull-up
const unsigned long DEBOUNCE_MS  = 40;
const unsigned long COOLDOWN_MS  = 3000;  // ignore repeat presses for 3 s
const unsigned long RESET_HOLD_MS = 5000;

bool lastStable = false;
bool lastRead = false;
unsigned long lastChange = 0;
unsigned long pressedAt = 0;
unsigned long lastStart = 0;
bool resetSent = false;

bool readPressed() {
  bool level = digitalRead(BUTTON_PIN) == HIGH;
  return ACTIVE_LOW ? !level : level;
}

void setup() {
  pinMode(BUTTON_PIN, ACTIVE_LOW ? INPUT_PULLUP : INPUT);
  pinMode(LED_BUILTIN, OUTPUT);
  Serial.begin(9600);
}

void loop() {
  unsigned long now = millis();
  bool r = readPressed();
  if (r != lastRead) { lastRead = r; lastChange = now; }

  if (now - lastChange >= DEBOUNCE_MS && r != lastStable) {
    lastStable = r;
    if (r) {
      pressedAt = now;
      resetSent = false;
      if (now - lastStart >= COOLDOWN_MS) {
        Serial.println("START");
        lastStart = now;
      }
    }
  }

  if (lastStable && !resetSent && now - pressedAt >= RESET_HOLD_MS) {
    Serial.println("RESET");
    resetSent = true;
  }

  digitalWrite(LED_BUILTIN, lastStable ? HIGH : LOW);  // on-board LED shows the button state
}
