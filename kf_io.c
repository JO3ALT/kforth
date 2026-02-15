#include "kf_io.h"
#include <stdio.h>

int mf_key(void){
  int c = getchar();
  if(c == EOF) return -1;
  return c & 0xFF;
}

void mf_emit(uint8_t ch){
  putchar((int)ch);
  fflush(stdout);
}
