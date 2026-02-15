#ifndef KF_IO_H
#define KF_IO_H

#include <stdint.h>

/* blocking read: return 0..255, or -1 on EOF */
int mf_key(void);

/* output one byte */
void mf_emit(uint8_t ch);

#endif
