/*
 * rp_pl_dev.c
 *
 *  Created on: 30 Sep 2014
 *      Author: nils
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/device.h>
#include <linux/err.h>
#include <linux/cdev.h>

static struct class *rp_pl_devclass;
static struct device *rp_pl_dev;

int rpad_setup_device_class(void)
{
	rp_pl_devclass = class_create(THIS_MODULE, "rpad");
	if (IS_ERR(rp_pl_devclass))
		return PTR_ERR(rp_pl_devclass);

	return 0;
}

void rpad_release_device_class(void)
{
	class_destroy(rp_pl_devclass);
}

int rpad_setup_device(struct device *busdevice, dev_t devt)
{
	rp_pl_dev = device_create(rp_pl_devclass, busdevice, devt, NULL,
	                          "rpad%d", MINOR(devt));
	if (IS_ERR(rp_pl_dev))
		return PTR_ERR(rp_pl_dev);

	return 0;
}

void rpad_release_device(dev_t devt)
{
	device_destroy(rp_pl_devclass, devt);
}
