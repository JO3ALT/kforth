#include <Arduino.h>

extern "C" int kforth_run(void);

#if defined(ARDUINO)
void setup() {
  Serial.begin(115200);
  delay(100);
  kforth_run();
}

void loop() {
  /* kforth_run() is blocking and owns the REPL loop. */
}
#endif
