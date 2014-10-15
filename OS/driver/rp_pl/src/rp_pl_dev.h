/*
 * rp_pl_dev.h
 *
 *  Created on: 30 Sep 2014
 *      Author: nils
 */

#ifndef RP_PL_DEV_H_
#define RP_PL_DEV_H_

#include <linux/device.h>

int rpad_setup_device_class(void);
void rpad_release_device_class(void);
int rpad_setup_device(struct device *busdevice, dev_t devt);
void rpad_release_device(dev_t devt);

#endif /* RP_PL_DEV_H_ */
