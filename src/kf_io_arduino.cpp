#include <Arduino.h>

extern "C" {
#include "kf_io.h"
}

#if defined(ARDUINO)
int mf_key(void) {
  while (Serial.available() <= 0) {
    delay(1);
  }
  return Serial.read() & 0xFF;
}

void mf_emit(uint8_t ch) {
  Serial.write(ch);
}
#endif
