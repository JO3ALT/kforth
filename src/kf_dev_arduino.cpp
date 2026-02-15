#include <Arduino.h>

extern "C" {
#include "kf_dev.h"
}

#if defined(ARDUINO)
/*
 * Handle map (minimal):
 *   0: Serial
 *
 * IOCTL request map for handle 0:
 *   0: available?    (x ignored) -> y=available bytes
 *   1: flush         (x ignored) -> y=0
 *   2: set baudrate  (x=baud)    -> y=baud
 */

int kf_io_at(int32_t h, int32_t *bout){
  if(h != 0){
    if(bout) *bout = 0;
    return 0;
  }
  if(Serial.available() <= 0){
    if(bout) *bout = 0;
    return 0;
  }
  if(bout) *bout = (int32_t)(Serial.read() & 0xFF);
  return 1;
}

int kf_io_put(int32_t h, int32_t b){
  if(h != 0) return 0;
  size_t n = Serial.write((uint8_t)(b & 0xFF));
  return (n == 1) ? 1 : 0;
}

int kf_io_ctl(int32_t h, int32_t req, int32_t x, int32_t *y){
  if(h != 0){
    if(y) *y = 0;
    return 0;
  }

  switch(req){
    case 0:
      if(y) *y = (int32_t)Serial.available();
      return 1;
    case 1:
      Serial.flush();
      if(y) *y = 0;
      return 1;
    case 2:
      if(x <= 0){
        if(y) *y = 0;
        return 0;
      }
      Serial.flush();
      Serial.begin((unsigned long)x);
      if(y) *y = x;
      return 1;
    default:
      if(y) *y = 0;
      return 0;
  }
}
#endif
