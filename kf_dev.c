#include "kf_dev.h"

int kf_io_at(int32_t h, int32_t *bout){
  (void)h;
  if(bout) *bout = 0;
  return 0;
}

int kf_io_put(int32_t h, int32_t b){
  (void)h;
  (void)b;
  return 0;
}

int kf_io_ctl(int32_t h, int32_t req, int32_t x, int32_t *y){
  (void)h;
  (void)req;
  (void)x;
  if(y) *y = 0;
  return 0;
}
