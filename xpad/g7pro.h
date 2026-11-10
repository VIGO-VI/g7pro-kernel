/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Pure GameSir G7 Pro report 0x10 decoder.
 *
 * Shared by the kernel driver and the userspace unit/fuzz tests.  It has no
 * kernel or input-subsystem dependencies beyond fixed-width types.
 */
#ifndef G7PRO_PROTO_H
#define G7PRO_PROTO_H

#ifdef __KERNEL__
#include <linux/types.h>
#include <linux/unaligned.h>
#define G7PRO_LE16(p) get_unaligned_le16(p)
#else
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef uint8_t u8;
typedef int16_t s16;
typedef uint16_t u16;
static inline u16 g7pro_le16(const u8 *p)
{
	return (u16)(p[0] | ((u16)p[1] << 8));
}
#define G7PRO_LE16(p) g7pro_le16(p)
#endif

#define G7PRO_REPORT_LEN	64
#define G7PRO_REPORT_ID		0x10
#define G7PRO_RESPONSE_MARKER	0x3c
#define G7PRO_INPUT_MARKER	0xe0

struct g7pro_state {
	u8 lx, ly, rx, ry;
	bool a, b, x, y;
	bool lb, rb, lt_digital, rt_digital;
	bool view, menu, l3, r3;
	bool guide, share, l4, r4, l5, r5;
	int hat_x, hat_y;
	u8 lt, rt;
	s16 gyro_x, gyro_y, gyro_z;
	s16 accel_x, accel_y, accel_z;
	int battery;
	bool charging;
};

/**
 * g7pro_decode_report - decode one 64-byte report 0x10 frame
 * @d: report bytes
 * @len: number of valid bytes
 * @s: decoded state
 *
 * Returns true for a valid input frame, false for anything else.  The
 * function never reads outside @len.
 */
static inline bool g7pro_decode_report(const u8 *d, size_t len,
				       struct g7pro_state *s)
{
	u8 b55, b56, b57, b58;

	if (!d || !s || len < 61)
		return false;
	if (d[0] != G7PRO_REPORT_ID || d[3] != G7PRO_RESPONSE_MARKER ||
	    d[4] != G7PRO_INPUT_MARKER)
		return false;

	*s = (struct g7pro_state){0};

	s->lx = d[5];
	s->ly = d[6];
	s->rx = d[7];
	s->ry = d[8];

	s->lt = d[12];
	s->rt = d[13];

	s->gyro_x = (s16)G7PRO_LE16(d + 17);
	s->gyro_y = (s16)G7PRO_LE16(d + 19);
	s->gyro_z = (s16)G7PRO_LE16(d + 21);
	s->accel_x = (s16)G7PRO_LE16(d + 23);
	s->accel_y = (s16)G7PRO_LE16(d + 25);
	s->accel_z = (s16)G7PRO_LE16(d + 27);

	s->battery = d[33] <= 100 ? d[33] : -1;
	s->charging = !!(d[32] & 1u);

	b55 = d[55];
	b56 = d[56];
	b57 = d[57];
	b58 = d[58];

	s->x = !!(b55 & 0x10);
	s->a = !!(b55 & 0x20);
	s->b = !!(b55 & 0x40);
	s->y = !!(b55 & 0x80);

	switch (b55 & 0x0f) {
	case 0x0:
		s->hat_y = -1;
		break;
	case 0x2:
		s->hat_x = 1;
		break;
	case 0x4:
		s->hat_y = 1;
		break;
	case 0x6:
		s->hat_x = -1;
		break;
	default:
		break;	/* 0xf = neutral */
	}

	s->lb = !!(b56 & (1u << 0));
	s->rb = !!(b56 & (1u << 1));
	s->lt_digital = !!(b56 & (1u << 2));
	s->rt_digital = !!(b56 & (1u << 3));
	s->view = !!(b56 & (1u << 4));
	s->menu = !!(b56 & (1u << 5));
	s->l3 = !!(b56 & (1u << 6));
	s->r3 = !!(b56 & (1u << 7));

	s->guide = !!(b57 & (1u << 0));
	s->share = !!(b57 & (1u << 1));
	s->l4 = !!(b57 & (1u << 3));
	s->r4 = !!(b57 & (1u << 4));

	s->l5 = !!(b58 & (1u << 0));
	s->r5 = !!(b58 & (1u << 1));

	return true;
}

#endif /* G7PRO_PROTO_H */
