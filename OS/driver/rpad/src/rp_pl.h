/*
 * rp_pl.h
 *
 *  Created on: 29 Sep 2014
 *      Author: nils
 */

#ifndef RP_PL_H_
#define RP_PL_H_

#include <linux/ioport.h>
#include <linux/semaphore.h>
#include <linux/device.h>
#include <linux/cdev.h>
#include <asm/io.h>

/*
 * root structure of the RPAD module
 * id			id value read from the PL
 * nr_of_regions	number of system bus regions supported by the PL
 * sys_res		resource pointer for our io allotment
 * sys_base		io cookie to use with ioread/iowrite/...
 * sem			access control
 */
struct rpad_sysconfig {
	u32			id;
	int			nr_of_regions;
	struct rpad_device	**rp_devs; /* TODO use a list ? */

	struct class		*devclass;
	void __iomem		*sys_base;
};

#define rp_sysa(sysconf,u)	((void __iomem *)((sysconf)->sys_base + (u)))

/*
 * this device structure is very much preliminary and guaranteed to change
 * substantially in order to accommodate enumerated subdevices etc. soonish
 *
 * sys_addr		physical address of the sys region
 * io_base		io cookie to use with ioread/iowrite/...
 * devt			this instance's device number pair
 * sem			access control
 * dev			device pointer
 * cdev			character device anchor
 */
struct rpad_device {
	resource_size_t 		sys_addr;
	void __iomem			*io_base;
	dev_t				devt;
	struct rpad_devtype_data	*data;
	struct semaphore		sem;
	struct device			*dev;
	struct cdev			cdev;
};

#define rp_addr(rpdev,u)	((void __iomem *)((rpdev)->rp_dev.io_base + (u)))

#endif /* RP_PL_H_ */
