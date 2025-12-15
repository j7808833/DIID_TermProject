#include <Arduino.h>

// Explicitly known pins to avoid
const int KNOWN_RED = 12;
const int KNOWN_GREEN = 13;

void setup() {
  Serial.begin(115200);
  while (!Serial); // Wait for Serial to be ready
  
  Serial.println("========================================");
  Serial.println("      LED Interactive Search Tool       ");
  Serial.println("========================================");
  Serial.println("Enter a pin number (0-40) to toggle it.");
  Serial.println("Type 'scan' to slowly cycle 0-20.");
  Serial.println("Known: Pin 12=Red, Pin 13=Green");
  Serial.println("----------------------------------------");
}

void loop() {
  if (Serial.available() > 0) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    
    if (input.equalsIgnoreCase("scan")) {
      Serial.println("Scanning pins 0 to 20...");
      for (int i = 0; i <= 20; i++) {
        if (i == KNOWN_RED || i == KNOWN_GREEN) continue;
        testPin(i);
      }
      Serial.println("Scan complete.");
    } else {
      int pin = input.toInt();
      if (pin == 0 && input != "0") {
        Serial.println("Invalid input. Type a number.");
      } else {
        testPin(pin);
      }
    }
  }
}

void testPin(int pin) {
  Serial.print("Testing Pin ");
  Serial.print(pin);
  Serial.print("... ");
  
  pinMode(pin, OUTPUT);
  // Flash LOW (Active ON for LEDs usually)
  digitalWrite(pin, LOW);
  delay(500);
  digitalWrite(pin, HIGH); // OFF
  delay(100);
  
  // Flash HIGH (Just in case Active HIGH)
  digitalWrite(pin, HIGH);
  delay(500);
  digitalWrite(pin, LOW); // OFF
  
  // Reset to INPUT to be safe
  pinMode(pin, INPUT);
  
  Serial.println("Done.");
}
