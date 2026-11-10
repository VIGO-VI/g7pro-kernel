// SPDX-License-Identifier: GPL-2.0-only
/*
 * Minimal force-feedback smoke test: upload one FF_RUMBLE effect, play it for
 * one second, stop it.  Run as root against the gamepad event node.
 *
 * cc -O2 -Wall -Wextra -o rumble_test rumble_test.c
 * ./rumble_test /dev/input/eventN
 */
#include <fcntl.h>
#include <linux/input.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	unsigned long ffbit[1 + FF_MAX / (8 * sizeof(unsigned long))] = {};
	struct ff_effect effect = {};
	struct input_event play = {};
	int fd;

	if (argc != 2) {
		fprintf(stderr, "usage: %s /dev/input/eventN\n", argv[0]);
		return 2;
	}

	fd = open(argv[1], O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror("open");
		return 1;
	}

	if (ioctl(fd, EVIOCGBIT(EV_FF, sizeof(ffbit)), ffbit) < 0) {
		perror("EVIOCGBIT");
		return 1;
	}
	if (!(ffbit[FF_RUMBLE / (8 * sizeof(unsigned long))] &
	      (1UL << (FF_RUMBLE % (8 * sizeof(unsigned long)))))) {
		fprintf(stderr, "%s does not advertise FF_RUMBLE\n", argv[1]);
		return 1;
	}

	effect.type = FF_RUMBLE;
	effect.id = -1;
	effect.u.rumble.strong_magnitude = 0xffff;
	effect.u.rumble.weak_magnitude = 0xffff;
	effect.replay.length = 1000;
	effect.replay.delay = 0;

	if (ioctl(fd, EVIOCSFF, &effect) < 0) {
		perror("EVIOCSFF");
		return 1;
	}

	play.type = EV_FF;
	play.code = effect.id;
	play.value = 1;
	if (write(fd, &play, sizeof(play)) != sizeof(play)) {
		perror("write play");
		return 1;
	}

	printf("rumble_test: playing 1 s\n");
	usleep(1000000);

	play.value = 0;
	(void)write(fd, &play, sizeof(play));
	(void)ioctl(fd, EVIOCRMFF, effect.id);
	close(fd);
	printf("rumble_test: OK\n");
	return 0;
}
