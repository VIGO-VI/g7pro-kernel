// SPDX-License-Identifier: GPL-2.0-only
//
// Emulate a non-GameSir xpad controller (045e:028e) on dummy_hcd, so the
// patched xpad can be compared against the stock one without another physical
// pad.  This is supplementary evidence: it proves the shared driver paths are
// unchanged for a non-G7 device, not that every real pad behaves the same.
//
//   sudo modprobe dummy_hcd raw_gadget
//   sudo ./build/fake_xpad
//
// The device appears as "Microsoft X-Box 360 pad" and is driven by xpad.

#include <errno.h>
#include <fcntl.h>
#include <linux/usb/ch9.h>
#include <linux/usb/raw_gadget.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

#define VENDOR 0x045e
#define PRODUCT 0x028e

static volatile sig_atomic_t running = 1;

static void on_sigint(int sig)
{
	(void)sig;
	running = 0;
}

static const struct usb_device_descriptor dev_desc = {
	.bLength = USB_DT_DEVICE_SIZE,
	.bDescriptorType = USB_DT_DEVICE,
	.bcdUSB = 0x0200,
	.bDeviceClass = 0,
	.bDeviceSubClass = 0,
	.bDeviceProtocol = 0,
	.bMaxPacketSize0 = 64,
	.idVendor = VENDOR,
	.idProduct = PRODUCT,
	.bcdDevice = 0x0114,
	.iManufacturer = 1,
	.iProduct = 2,
	.iSerialNumber = 3,
	.bNumConfigurations = 1,
};

/* Endpoint descriptors are 7 bytes on the wire; struct usb_endpoint_descriptor
 * is 9 (it carries audio-only fields), so it must not be embedded here. */
struct ep_desc {
	__u8 bLength;
	__u8 bDescriptorType;
	__u8 bEndpointAddress;
	__u8 bmAttributes;
	__u16 wMaxPacketSize;
	__u8 bInterval;
} __attribute__((packed));

struct config_blob {
	struct usb_config_descriptor config;
	struct usb_interface_descriptor intf;
	struct ep_desc ep_in;
	struct ep_desc ep_out;
} __attribute__((packed));

static const struct usb_qualifier_descriptor qualifier = {
	.bLength = sizeof(struct usb_qualifier_descriptor),
	.bDescriptorType = USB_DT_DEVICE_QUALIFIER,
	.bcdUSB = 0x0200,
	.bDeviceClass = 0,
	.bDeviceSubClass = 0,
	.bDeviceProtocol = 0,
	.bMaxPacketSize0 = 64,
	.bNumConfigurations = 1,
	.bRESERVED = 0,
};

static const struct config_blob config = {
	.config = {
		.bLength = USB_DT_CONFIG_SIZE,
		.bDescriptorType = USB_DT_CONFIG,
		.wTotalLength = sizeof(struct config_blob),
		.bNumInterfaces = 1,
		.bConfigurationValue = 1,
		.iConfiguration = 0,
		.bmAttributes = 0x80,
		.bMaxPower = 50,
	},
	.intf = {
		.bLength = USB_DT_INTERFACE_SIZE,
		.bDescriptorType = USB_DT_INTERFACE,
		.bInterfaceNumber = 0,
		.bAlternateSetting = 0,
		.bNumEndpoints = 2,
		/* xpad matches vendor-wide entries by class/subclass/protocol:
		 * USB_CLASS_VENDOR_SPEC, 93, 1 (Xbox 360). */
		.bInterfaceClass = 0xff,
		.bInterfaceSubClass = 93,
		.bInterfaceProtocol = 1,
		.iInterface = 0,
	},
	.ep_in = {
		.bLength = USB_DT_ENDPOINT_SIZE,
		.bDescriptorType = USB_DT_ENDPOINT,
		.bEndpointAddress = 0x81,
		.bmAttributes = USB_ENDPOINT_XFER_INT,
		.wMaxPacketSize = 32,
		.bInterval = 4,
	},
	.ep_out = {
		.bLength = USB_DT_ENDPOINT_SIZE,
		.bDescriptorType = USB_DT_ENDPOINT,
		.bEndpointAddress = 0x02,
		.bmAttributes = USB_ENDPOINT_XFER_INT,
		.wMaxPacketSize = 32,
		.bInterval = 8,
	},
};

static int ep0_write(int fd, const void *data, unsigned int len)
{
	unsigned char buf[sizeof(struct usb_raw_ep_io) + 512];
	struct usb_raw_ep_io *io = (struct usb_raw_ep_io *)buf;

	io->ep = 0;
	io->flags = 0;
	io->length = len;
	memcpy(io->data, data, len);
	return ioctl(fd, USB_RAW_IOCTL_EP0_WRITE, io);
}

static int ep0_read(int fd, unsigned int len)
{
	unsigned char buf[sizeof(struct usb_raw_ep_io) + 512];
	struct usb_raw_ep_io *io = (struct usb_raw_ep_io *)buf;

	io->ep = 0;
	io->flags = 0;
	io->length = len;
	return ioctl(fd, USB_RAW_IOCTL_EP0_READ, io);
}

static int send_string(int fd, int index, unsigned int wlen)
{
	static char buf[256];
	unsigned char *p;
	const char *s = "";
	int n, i;

	switch (index) {
	case 0: {
		static const unsigned char lang[4] = { 4, USB_DT_STRING, 0x09, 0x04 };
		return ep0_write(fd, lang, wlen < 4 ? wlen : 4);
	}
	case 1: s = "OpenCode"; break;
	case 2: s = "Fake Xbox 360 Pad"; break;
	case 3: s = "0001"; break;
	default: return ioctl(fd, USB_RAW_IOCTL_EP0_STALL, 0);
	}

	n = strlen(s);
	buf[0] = 2 + 2 * n;
	buf[1] = USB_DT_STRING;
	p = (unsigned char *)buf + 2;
	for (i = 0; i < n; i++) {
		p[2 * i] = s[i];
		p[2 * i + 1] = 0;
	}
	i = buf[0];
	if ((unsigned int)i > wlen) i = wlen;
	return ep0_write(fd, buf, i);
}

static int handle_control(int fd, const struct usb_ctrlrequest *ctrl)
{
	unsigned int wlen = ctrl->wLength;
	unsigned char small[2] = { 0, 0 };

	printf("ctrl %02x %02x value=%04x index=%04x len=%u\n",
	       ctrl->bRequestType, ctrl->bRequest, ctrl->wValue,
	       ctrl->wIndex, ctrl->wLength);
	fflush(stdout);

	if ((ctrl->bRequestType & USB_TYPE_MASK) != USB_TYPE_STANDARD)
		return ioctl(fd, USB_RAW_IOCTL_EP0_STALL, 0);

	switch (ctrl->bRequest) {
	case USB_REQ_GET_DESCRIPTOR: {
		int type = ctrl->wValue >> 8;
		int index = ctrl->wValue & 0xff;

		if (type == USB_DT_DEVICE) {
			unsigned int n = sizeof(dev_desc);
			return ep0_write(fd, &dev_desc, wlen < n ? wlen : n);
		}
		if (type == USB_DT_DEVICE_QUALIFIER) {
			unsigned int n = sizeof(qualifier);
			return ep0_write(fd, &qualifier, wlen < n ? wlen : n);
		}
		if (type == USB_DT_CONFIG) {
			unsigned int n = sizeof(config);
			return ep0_write(fd, &config, wlen < n ? wlen : n);
		}
		if (type == USB_DT_STRING)
			return send_string(fd, index, wlen);
		return ioctl(fd, USB_RAW_IOCTL_EP0_STALL, 0);
	}
	case USB_REQ_SET_CONFIGURATION:
		/* Acknowledge immediately.  Enabling endpoints here blocks: the UDC
		 * is not configured until this status stage completes.  xpad only
		 * reads descriptors at probe, so no endpoint is needed. */
		return ep0_read(fd, 0);
	case USB_REQ_SET_INTERFACE:
		return ep0_read(fd, 0);
	case USB_REQ_GET_STATUS:
		return ep0_write(fd, small, wlen < 2 ? wlen : 2);
	case USB_REQ_GET_CONFIGURATION:
		small[0] = 1;
		return ep0_write(fd, small, wlen < 1 ? wlen : 1);
	default:
		return ioctl(fd, USB_RAW_IOCTL_EP0_STALL, 0);
	}
}

int main(void)
{
	struct usb_raw_init init = { 0 };
	unsigned char evbuf[sizeof(struct usb_raw_event) + 1024];
	struct usb_raw_event *ev = (struct usb_raw_event *)evbuf;
	int fd;

	signal(SIGINT, on_sigint);
	signal(SIGTERM, on_sigint);

	printf("sizes: device=%zu config=%zu interface=%zu ep=%zu blob=%zu\n",
	       sizeof(dev_desc), sizeof(struct usb_config_descriptor),
	       sizeof(struct usb_interface_descriptor), sizeof(struct ep_desc),
	       sizeof(config));
	fflush(stdout);

	fd = open("/dev/raw-gadget", O_RDWR);
	if (fd < 0) {
		perror("open /dev/raw-gadget (modprobe raw_gadget)");
		return 1;
	}

	snprintf((char *)init.driver_name, UDC_NAME_LENGTH_MAX, "dummy_udc");
	snprintf((char *)init.device_name, UDC_NAME_LENGTH_MAX, "dummy_udc.0");
	init.speed = USB_SPEED_HIGH;

	if (ioctl(fd, USB_RAW_IOCTL_INIT, &init) < 0) {
		perror("USB_RAW_IOCTL_INIT (modprobe dummy_hcd)");
		return 1;
	}
	if (ioctl(fd, USB_RAW_IOCTL_RUN, 0) < 0) {
		perror("USB_RAW_IOCTL_RUN");
		return 1;
	}
	printf("fake xpad %04x:%04x running\n", VENDOR, PRODUCT);
	fflush(stdout);

	while (running) {
		unsigned int len = sizeof(evbuf) - sizeof(struct usb_raw_event);

		memset(ev, 0, sizeof(evbuf));
		ev->length = len;
		if (ioctl(fd, USB_RAW_IOCTL_EVENT_FETCH, ev) < 0) {
			if (errno == EINTR) continue;
			perror("EVENT_FETCH");
			break;
		}
		if (ev->type == USB_RAW_EVENT_CONTROL)
			handle_control(fd,
				(const struct usb_ctrlrequest *)ev->data);
	}

	close(fd);
	return 0;
}
