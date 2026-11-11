// SPDX-License-Identifier: GPL-2.0-only
// Print accelerometer variance in 100 ms windows with CLOCK_MONOTONIC
// timestamps, so it can be correlated with dmesg while the pad vibrates.
//
// cc -static -O2 -o accel_watch accel_watch.c
// ./accel_watch /dev/input/eventN [duration_ms]
#include <fcntl.h>
#include <linux/input.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/ioctl.h>
#include <unistd.h>

static double mono(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	unsigned int duration_ms = 3000;
	int fd, ax = 0, ay = 0, az = 0;

	if (argc < 2 || argc > 3) {
		fprintf(stderr, "usage: %s /dev/input/eventN [ms]\n", argv[0]);
		return 2;
	}
	if (argc == 3)
		duration_ms = (unsigned int)strtoul(argv[2], NULL, 10);

	fd = open(argv[1], O_RDONLY | O_NONBLOCK);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	{
		char name[128] = "?";

		ioctl(fd, EVIOCGNAME(sizeof(name)), name);
		printf("watch device=%s\n", name);
	}

	const double end = mono() + duration_ms / 1000.0;
	double win_end = mono() + 0.1;
	double sum = 0, sum2 = 0;
	int n = 0;

	while (mono() < end) {
		struct input_event ev;
		ssize_t r = read(fd, &ev, sizeof(ev));

		if (r == sizeof(ev)) {
			if (ev.type == EV_ABS) {
				if (ev.code == ABS_X) ax = ev.value;
				else if (ev.code == ABS_Y) ay = ev.value;
				else if (ev.code == ABS_Z) az = ev.value;
			} else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
				double m = sqrt((double)ax * ax + (double)ay * ay +
						(double)az * az);
				sum += m;
				sum2 += m * m;
				n++;
			}
		} else {
			usleep(2000);
		}

		if (mono() >= win_end) {
			{
				double mean = n ? sum / n : 0;
				double var = n ? sum2 / n - mean * mean : 0;
				printf("watch t=%.2f sd=%.1f n=%d\n", win_end,
				       var > 0 ? sqrt(var) : 0.0, n);
			}
			sum = sum2 = 0;
			n = 0;
			win_end += 0.1;
		}
	}

	printf("watch done, windows=%d\n", (int)(duration_ms / 100));
	close(fd);
	return 0;
}
