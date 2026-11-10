// SPDX-License-Identifier: GPL-2.0-only
/*
 * Dump evdev capabilities in a stable form, for structural comparison
 * between xpad and g7pro.  Run as root.
 *
 * cc -O2 -Wall -Wextra -o evdev_caps evdev_caps.c
 * ./evdev_caps /dev/input/eventN
 */
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define BITS_PER_LONG (8 * sizeof(unsigned long))
#define NBITS(x) (((x) + BITS_PER_LONG - 1) / BITS_PER_LONG)
#define TEST_BIT(bit, array) \
	((array)[(bit) / BITS_PER_LONG] & (1UL << ((bit) % BITS_PER_LONG)))

static void dump_bits(const char *label, const unsigned long *bits, int max)
{
	printf("%s:", label);
	for (int i = 0; i <= max; i++)
		if (TEST_BIT(i, bits))
			printf(" %d", i);
	printf("\n");
}

int main(int argc, char **argv)
{
	unsigned long evbit[NBITS(EV_MAX)] = {};
	unsigned long keybit[NBITS(KEY_MAX)] = {};
	unsigned long absbit[NBITS(ABS_MAX)] = {};
	unsigned long ffbit[NBITS(FF_MAX)] = {};
	unsigned long propbit[NBITS(INPUT_PROP_MAX)] = {};
	char name[256] = "?";
	struct input_id id = {};
	int fd;

	if (argc != 2) {
		fprintf(stderr, "usage: %s /dev/input/eventN\n", argv[0]);
		return 2;
	}

	fd = open(argv[1], O_RDONLY | O_CLOEXEC);
	if (fd < 0) {
		perror("open");
		return 1;
	}

	(void)ioctl(fd, EVIOCGNAME(sizeof(name) - 1), name);
	(void)ioctl(fd, EVIOCGID, &id);
	(void)ioctl(fd, EVIOCGBIT(0, sizeof(evbit)), evbit);
	(void)ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybit)), keybit);
	(void)ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(absbit)), absbit);
	(void)ioctl(fd, EVIOCGBIT(EV_FF, sizeof(ffbit)), ffbit);
	(void)ioctl(fd, EVIOCGPROP(sizeof(propbit)), propbit);

	printf("device=%s\n", name);
	printf("id=%04x:%04x version=%04x bustype=%04x\n",
	       id.vendor, id.product, id.version, id.bustype);
	dump_bits("ev", evbit, EV_MAX);
	dump_bits("key", keybit, KEY_MAX);
	dump_bits("abs", absbit, ABS_MAX);
	dump_bits("ff", ffbit, FF_MAX);
	dump_bits("prop", propbit, INPUT_PROP_MAX);

	for (int i = 0; i <= ABS_MAX; i++) {
		struct input_absinfo ai;

		if (!TEST_BIT(i, absbit))
			continue;
		if (ioctl(fd, EVIOCGABS(i), &ai) < 0)
			continue;
		printf("absinfo %d: min=%d max=%d fuzz=%d flat=%d res=%d\n",
		       i, ai.minimum, ai.maximum, ai.fuzz, ai.flat,
		       ai.resolution);
	}

	close(fd);
	return 0;
}
