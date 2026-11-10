// SPDX-License-Identifier: GPL-2.0-only
/*
 * Capture one report 0x10 frame from a wired GameSir G7 Pro.
 * Used to build golden parser fixtures; not part of the kernel module.
 *
 * cc -O2 -Wall -Wextra -o capture_report capture_report.c \
 *    $(pkg-config --cflags --libs libusb-1.0)
 */
#include <libusb-1.0/libusb.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define VID 0x3537
#define PID 0x109b
#define EP_IN 0x82
#define EP_OUT 0x02

static int heartbeat(libusb_device_handle *h, uint8_t seq)
{
	uint8_t pkt[64] = {};

	pkt[0] = 0x0f;
	pkt[2] = seq;
	pkt[3] = 0x02;
	pkt[4] = 0xf2;

	int transferred = 0;
	return libusb_interrupt_transfer(h, EP_OUT, pkt, sizeof(pkt),
					 &transferred, 1000);
}

int main(void)
{
	libusb_context *ctx = NULL;
	libusb_device **list = NULL;
	libusb_device_handle *h = NULL;
	ssize_t count;
	int rc;

	if (libusb_init(&ctx) != 0)
		return 1;

	count = libusb_get_device_list(ctx, &list);
	if (count < 0)
		return 1;

	for (ssize_t i = 0; i < count; i++) {
		struct libusb_device_descriptor d;

		if (libusb_get_device_descriptor(list[i], &d) != 0)
			continue;
		if (d.idVendor == VID && d.idProduct == PID) {
			rc = libusb_open(list[i], &h);
			if (rc == 0)
				break;
		}
	}
	libusb_free_device_list(list, 1);

	if (!h) {
		fprintf(stderr, "G7 Pro not found\n");
		return 1;
	}

	(void)libusb_set_auto_detach_kernel_driver(h, 1);
	rc = libusb_claim_interface(h, 0);
	if (rc != 0) {
		fprintf(stderr, "claim failed: %s\n", libusb_error_name(rc));
		return 1;
	}

	for (uint8_t i = 0; i < 4; i++) {
		heartbeat(h, i + 1);
		usleep(250000);
	}

	for (int tries = 0; tries < 200; tries++) {
		uint8_t buf[64] = {};
		int transferred = 0;

		rc = libusb_interrupt_transfer(h, EP_IN, buf, sizeof(buf),
					       &transferred, 1000);
		if (rc == LIBUSB_ERROR_TIMEOUT)
			continue;
		if (rc != 0) {
			fprintf(stderr, "read failed: %s\n",
				libusb_error_name(rc));
			break;
		}
		if (transferred >= 61 && buf[0] == 0x10 &&
		    buf[3] == 0x3c && buf[4] == 0xe0) {
			for (int j = 0; j < transferred; j++)
				printf("%02x", buf[j]);
			printf("\n");
			break;
		}
	}

	(void)libusb_release_interface(h, 0);
	libusb_close(h);
	libusb_exit(ctx);
	return 0;
}
