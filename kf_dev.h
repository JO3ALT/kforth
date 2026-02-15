#ifndef KF_DEV_H
#define KF_DEV_H

#include <stdint.h>

/*
 * Device I/O backend hooks for generic Forth I/O primitives.
 * Return 1 on success, 0 on failure/no-data.
 */
int kf_io_at(int32_t h, int32_t *bout);                 /* IO@   ( h -- b f ) */
int kf_io_put(int32_t h, int32_t b);                    /* IO!   ( b h -- f ) */
int kf_io_ctl(int32_t h, int32_t req, int32_t x, int32_t *y); /* IOCTL ( x req h -- y f ) */

#endif
