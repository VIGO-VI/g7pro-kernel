// SPDX-License-Identifier: GPL-2.0-only
/*
 * Unit tests for the pure report 0x10 decoder.
 *
 * Build/run:
 *   cc -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
 *      -I.. -o parser_test parser_test.c
 *   ./parser_test
 */
#include "g7pro_proto.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int failures;

#define CHECK(cond) do { \
	if (!(cond)) { \
		fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
		failures++; \
	} \
} while (0)

static void put16(uint8_t *p, int16_t v)
{
	p[0] = (uint8_t)(v & 0xff);
	p[1] = (uint8_t)((v >> 8) & 0xff);
}

static void test_valid_frame(void)
{
	uint8_t f[64] = {};
	struct g7pro_state s;

	f[0] = 0x10;
	f[3] = 0x3c;
	f[4] = 0xe0;

	f[5] = 0x80;
	f[6] = 0x80;
	f[7] = 0x7d;
	f[8] = 0x80;
	f[12] = 17;
	f[13] = 200;

	put16(f + 17, 1);
	put16(f + 19, -2);
	put16(f + 21, 3);
	put16(f + 23, 10);
	put16(f + 25, 8290);
	put16(f + 27, -20);

	f[32] = 1;
	f[33] = 87;

	f[55] = 0x20;	/* A + D-pad up */
	f[56] = 0x55;	/* LB, LT, View, L3 */
	f[57] = 0x1b;	/* Guide, Share, L4, R4 */
	f[58] = 0x03;	/* L5, R5 */

	CHECK(g7pro_decode_report(f, sizeof(f), &s));
	CHECK(s.lx == 0x80 && s.ly == 0x80 && s.rx == 0x7d && s.ry == 0x80);
	CHECK(s.lt == 17 && s.rt == 200);
	CHECK(s.gyro_x == 1 && s.gyro_y == -2 && s.gyro_z == 3);
	CHECK(s.accel_x == 10 && s.accel_y == 8290 && s.accel_z == -20);
	CHECK(s.battery == 87 && s.charging);
	CHECK(s.a && !s.b && !s.x && !s.y);
	CHECK(s.hat_x == 0 && s.hat_y == -1);
	CHECK(s.lb && s.lt_digital && s.view && s.l3);
	CHECK(!s.rb && !s.rt_digital && !s.menu && !s.r3);
	CHECK(s.guide && s.share && s.l4 && s.r4);
	CHECK(s.l5 && s.r5);
}


static void test_live_golden_frame(void)
{
	/* Captured from a wired 3537:109b on 2026-11-10. */
	static const uint8_t f[64] = {
	0x10, 0x00, 0xb4, 0x3c, 0xe0, 0x80, 0x80, 0x7d, 0x80, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0xff, 0xff, 0xff, 0xff, 0x00, 0x00, 0x98, 0xff, 0x52, 0x20, 0xa9, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x64, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x84, 0x81, 0x7f, 0x80, 0x0f, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	};
	struct g7pro_state s;

	CHECK(g7pro_decode_report(f, sizeof(f), &s));
	CHECK(s.lx == 0x80 && s.ly == 0x80 && s.rx == 0x7d && s.ry == 0x80);
	CHECK(s.lt == 0 && s.rt == 0);
	CHECK(s.gyro_x == -1 && s.gyro_y == -1 && s.gyro_z == 0);
	CHECK(s.accel_x == -104 && s.accel_y == 8274 && s.accel_z == 169);
	CHECK(s.battery == 100 && !s.charging);
	CHECK(!s.a && !s.b && !s.x && !s.y);
	CHECK(s.hat_x == 0 && s.hat_y == 0);
	CHECK(!s.lb && !s.rb && !s.view && !s.menu && !s.l3 && !s.r3);
	CHECK(!s.guide && !s.share && !s.l4 && !s.r4 && !s.l5 && !s.r5);
}

static void test_rejects_bad_frames(void)
{
	uint8_t f[64] = {};
	struct g7pro_state s;

	f[0] = 0x10;
	f[3] = 0x3c;
	f[4] = 0xe0;

	CHECK(!g7pro_decode_report(f, 60, &s));
	CHECK(!g7pro_decode_report(NULL, 64, &s));
	CHECK(!g7pro_decode_report(f, 64, NULL));

	f[0] = 0x11;
	CHECK(!g7pro_decode_report(f, 64, &s));
	f[0] = 0x10;
	f[3] = 0x3d;
	CHECK(!g7pro_decode_report(f, 64, &s));
	f[3] = 0x3c;
	f[4] = 0xe1;
	CHECK(!g7pro_decode_report(f, 64, &s));

	f[4] = 0xe0;
	f[33] = 200;
	CHECK(g7pro_decode_report(f, 64, &s));
	CHECK(s.battery == -1);
}

static void test_dpad_neutral(void)
{
	uint8_t f[64] = {};
	struct g7pro_state s;

	f[0] = 0x10;
	f[3] = 0x3c;
	f[4] = 0xe0;
	f[55] = 0x0f;
	CHECK(g7pro_decode_report(f, 64, &s));
	CHECK(s.hat_x == 0 && s.hat_y == 0);
}

static void fuzz_parser(void)
{
	uint8_t f[64];
	uint32_t x = 0x12345678;

	for (unsigned i = 0; i < 200000; i++) {
		struct g7pro_state s;
		size_t len;

		x ^= x << 13;
		x ^= x >> 17;
		x ^= x << 5;
		len = x % (sizeof(f) + 1);

		for (size_t j = 0; j < sizeof(f); j++) {
			x ^= x << 13;
			x ^= x >> 17;
			x ^= x << 5;
			f[j] = (uint8_t)x;
		}
		(void)g7pro_decode_report(f, len, &s);
	}
}

int main(void)
{
	test_valid_frame();
	test_live_golden_frame();
	test_rejects_bad_frames();
	test_dpad_neutral();
	fuzz_parser();

	if (failures) {
		fprintf(stderr, "%d failure(s)\n", failures);
		return 1;
	}
	printf("parser tests: OK\n");
	return 0;
}
