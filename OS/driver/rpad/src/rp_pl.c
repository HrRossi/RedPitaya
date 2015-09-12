/*
 * rp_pl.c
 *
 *  Created on: 26 Sep 2014
 *      Author: nils
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/types.h>
#include <linux/errno.h>
#include <linux/slab.h>
#include <linux/fs.h>

#include "rp_pl_hw.h"
#include "rp_pl.h"

static unsigned int		major = 0;
static unsigned int		minor = 0;

static struct rpad_sysconfig	rpad_sys;

/*
 * create mapping to sysconfig io address block.
 */
static int rpad_map_sysconfig_io(void)
{
	if (!request_mem_region(RPAD_PL_SYS_RESERVED,
	                        RPAD_PL_END - RPAD_PL_SYS_RESERVED,
	                        "rpad_sysconfig"))
		return -EBUSY;

	rpad_sys.sys_base =
		ioremap_nocache(RPAD_PL_SYS_RESERVED,
		                RPAD_PL_END - RPAD_PL_SYS_RESERVED);
	if (!rpad_sys.sys_base) {
		release_mem_region(RPAD_PL_SYS_RESERVED,
		                   RPAD_PL_END - RPAD_PL_SYS_RESERVED);
		return -EBUSY;
	}

	return 0;
}

/*
 * release sysconfig io address block.
 */
static inline void rpad_unmap_sysconfig_io(void)
{
	iounmap(rpad_sys.sys_base);
	release_mem_region(RPAD_PL_SYS_RESERVED,
	                   RPAD_PL_END - RPAD_PL_SYS_RESERVED);
}

/*
 * prepare architectural components.
 * - major/minor device number(s) given through module params and sysconfig
 *   enumeration.
 * - "rpad" device class
 */
static int rpad_prepare_architecture(void)
{
	int ret;
	dev_t devt;

	if (major) {
		devt = MKDEV(major, minor);
		ret = register_chrdev_region(devt, rpad_sys.nr_of_regions,
		                             "rpad");
	} else {
		ret = alloc_chrdev_region(&devt, minor, rpad_sys.nr_of_regions,
		                          "rpad");
	}
	if (ret < 0) {
		printk(KERN_WARNING "rpad: can't get major %u\n", major);
		return ret;
	}
	major = MAJOR(devt);

	rpad_sys.devclass = class_create(THIS_MODULE, "rpad");
	if (IS_ERR(rpad_sys.devclass)) {
		printk(KERN_WARNING "rpad: class setup error\n");
		unregister_chrdev_region(MKDEV(major, minor),
		                         rpad_sys.nr_of_regions);
		return PTR_ERR(rpad_sys.devclass);
	}

	printk(KERN_INFO "rpad: registered as %u:%u-%u\n", major, minor,
	       minor + rpad_sys.nr_of_regions - 1);

	return 0;
}

/*
 * reverse preparations.
 */
static inline void rpad_unprepare_architecture(void)
{
	class_destroy(rpad_sys.devclass);
	unregister_chrdev_region(MKDEV(major, minor), rpad_sys.nr_of_regions);
}

/*
 * prepare rpad_device's common components and register them with the kernel.
 * only things that can legally be copied into the final subtype structure later
 * are prepared here:
 * - device number
 * - pointer to device
 * - io mapping
 */
static int rpad_prepare_device(struct rpad_device *rp_dev,
                               dev_t devt,
                               int region_nr,
                               unsigned int sub_minor)
{
	struct rpad_devtype_data *data = rp_dev->data;

	rp_dev->sys_addr = RPAD_PL_BASE + region_nr * RPAD_PL_REGION_SIZE;
	rp_dev->devt = devt;

	rp_dev->dev = device_create(rpad_sys.devclass, NULL, devt, NULL,
	                            "rpad_%s%d", data->name, sub_minor);
	if (IS_ERR(rp_dev->dev)) {
		printk(KERN_WARNING "rpad_%s%d: setup error\n", data->name,
		       sub_minor);
		return PTR_ERR(rp_dev->dev);
	}

	if (!request_mem_region(rp_dev->sys_addr, RPAD_PL_REGION_SIZE,
	                        dev_name(rp_dev->dev))) {
		printk(KERN_WARNING "%s: io region blocked\n",
		       dev_name(rp_dev->dev));
		device_destroy(rpad_sys.devclass, devt);
		return -EBUSY;
	}

	rp_dev->io_base = ioremap_nocache(rp_dev->sys_addr,
	                                  RPAD_PL_REGION_SIZE);
	if (!rp_dev->io_base) {
		printk(KERN_WARNING "%s: io remap failed\n",
		       dev_name(rp_dev->dev));
		release_mem_region(rp_dev->sys_addr, RPAD_PL_REGION_SIZE);
		device_destroy(rpad_sys.devclass, devt);
		return -EBUSY;
	}

	return 0;
}

/*
 * reverse preparations.
 */
static void rpad_unprepare_device(struct rpad_device *rp_dev)
{
	iounmap(rp_dev->io_base);
	release_mem_region(rp_dev->sys_addr, RPAD_PL_REGION_SIZE);
	device_destroy(rpad_sys.devclass, rp_dev->devt);
}

/*
 * unregister interrupt handlers
 */
static void rpad_unregister_interrupts(struct rpad_device *rp_dev)
{
	if (rp_dev->hw_config.irq0_id)
		free_irq(rp_dev->hw_config.irq0_id, rp_dev);
	if (rp_dev->hw_config.irq1_id)
		free_irq(rp_dev->hw_config.irq1_id, rp_dev);
	if (rp_dev->hw_config.irq2_id)
		free_irq(rp_dev->hw_config.irq2_id, rp_dev);
	if (rp_dev->hw_config.irq3_id)
		free_irq(rp_dev->hw_config.irq3_id, rp_dev);
}

/*
 * initialize mutex and char device. register interrupt handlers, if needed.
 * register rpad_device's char device with the kernel, making it go live.
 */
static int rpad_activate_device(struct rpad_device *rp_dev, int region)
{
	int ret;
	const char *name = dev_name(rp_dev->dev);

	mutex_init(&rp_dev->mtx);

	cdev_init(&rp_dev->cdev, rp_dev->data->fops);
	rp_dev->cdev.owner = THIS_MODULE;

	if (rp_dev->data->iops) {
		struct irq_handlers *h = rp_dev->data->iops;
		struct rpad_irq_config irqs;

		rpad_get_irq_config(&rpad_sys, region, &irqs);
		if (irqs.irq0_id && h->irq0_handler &&
		    !request_irq(irqs.irq0_id, h->irq0_handler, 0, name, rp_dev))
			rp_dev->hw_config.irq0_id = irqs.irq0_id;
		if (irqs.irq1_id && h->irq1_handler &&
		    !request_irq(irqs.irq1_id, h->irq1_handler, 0, name, rp_dev))
			rp_dev->hw_config.irq1_id = irqs.irq1_id;
		if (irqs.irq2_id && h->irq2_handler &&
		    !request_irq(irqs.irq2_id, h->irq2_handler, 0, name, rp_dev))
			rp_dev->hw_config.irq2_id = irqs.irq2_id;
		if (irqs.irq3_id && h->irq3_handler &&
		    !request_irq(irqs.irq3_id, h->irq3_handler, 0, name, rp_dev))
			rp_dev->hw_config.irq3_id = irqs.irq3_id;
	}

	ret = cdev_add(&rp_dev->cdev, rp_dev->devt, 1);
	if (ret) {
		printk(KERN_WARNING "%s: can't add char device\n", name);
		rpad_unregister_interrupts(rp_dev);
		return ret;
	}

	return 0;
}

/*
 * search all supported devices in the RPAD PL regions and install the
 * appropriate device implementation for each recognized instance.
 */
static int rpad_install_devices(void)
{
	int region;
	unsigned int next_minor;
	struct rpad_device temp_dev;
	struct rpad_device *rp_dev;
	enum rpad_devtype sub_type;
	unsigned int sub_minors[NUM_RPAD_TYPES];
	int ret;

	rpad_sys.rp_devs =
		kzalloc(rpad_sys.nr_of_regions * sizeof(struct rpad_device *),
		        GFP_KERNEL);
	if (!rpad_sys.rp_devs)
		return -ENOMEM;

	memset(sub_minors, 0, sizeof(sub_minors));
	next_minor = minor;
	for (region = 0; region < rpad_sys.nr_of_regions; region++) {
		memset(&temp_dev, 0, sizeof(temp_dev));

		/* hardware interrogation */
		temp_dev.data = rpad_get_devtype_data(region,
		                                      &temp_dev.hw_config);
		if (IS_ERR(temp_dev.data))
			continue;
		sub_type = temp_dev.data->type;

		/* device recognized, installation in 4 steps */
		ret = rpad_prepare_device(&temp_dev, MKDEV(major, next_minor),
		                          region, sub_minors[sub_type]);
		if (ret) {
			printk(KERN_INFO "rpad: skipped device, rc %d\n", ret);
			continue;
		}

		rp_dev = temp_dev.data->setup(&temp_dev);
		if (IS_ERR(rp_dev)) {
			printk(KERN_INFO "rpad: skipped device, rc %ld\n",
			       PTR_ERR(rp_dev));
			rpad_unprepare_device(&temp_dev);
			continue;
		}

		ret = rpad_activate_device(rp_dev, region);
		if (ret) {
			printk(KERN_INFO "rpad: skipped device, rc %d\n", ret);
			rp_dev->data->teardown(rp_dev);
			rpad_unprepare_device(&temp_dev);
			continue;
		}

		rpad_sys.rp_devs[next_minor - minor] = rp_dev;
		/* TODO we just stored an indirect reference to a device here.
		 * do we need to get_device, or was that implicit with create in
		 * rpad_prepare_device() ? how about the cdev ? */
		sub_minors[sub_type]++;
		next_minor++;
	}

	if (next_minor == minor) {
		kfree(rpad_sys.rp_devs);
		return -ENXIO; /* not a single device installed */
	}

	return 0;
}

/*
 * uninstall all previously installed device implementations.
 */
static void rpad_uninstall_devices(void)
{
	int i;
	struct rpad_device temp_dev;
	struct rpad_device *rp_dev;

	for (i = 0; i < rpad_sys.nr_of_regions; i++) {
		if (!(rp_dev = rpad_sys.rp_devs[i]))
			break;
		/* TODO see above re put_device etc */
		cdev_del(&rp_dev->cdev);
		rpad_unregister_interrupts(rp_dev);
		temp_dev = *rp_dev; /* make a copy, teardown() frees rp_dev */
		rp_dev->data->teardown(rp_dev);
		rpad_unprepare_device(&temp_dev);
	}
	kfree(rpad_sys.rp_devs);
}

/*
 * initialize module resources, scan for devices
 */
static int __init rpad_init(void)
{
	int ret;

	ret = rpad_map_sysconfig_io();
	if (ret)
		goto error_msg;

	if (!rpad_check_sysconfig(&rpad_sys)) {
		printk(KERN_INFO "rpad: no supported RPAD PL found\n");
		ret = -ENXIO;
		goto error_unmap;
	}

	ret = rpad_prepare_architecture();
	if (ret)
		goto error_unmap;

	ret = rpad_install_devices();
	if (ret)
		goto error_unprep;

	printk(KERN_INFO "Module rpad loaded\n");

	return 0;

error_unprep:
	rpad_unprepare_architecture();
error_unmap:
	rpad_unmap_sysconfig_io();
error_msg:
	printk(KERN_INFO "Module rpad not loaded\n");

	return ret;
}

/*
 * release all module resources
 */
static void __exit rpad_exit(void)
{
	rpad_uninstall_devices();
	rpad_unprepare_architecture();
	rpad_unmap_sysconfig_io();

	printk(KERN_INFO "Module rpad unloaded\n");
}

/*
 * supported parameters on the insmod command line
 */
module_param(major, uint, S_IRUGO);
module_param(minor, uint, S_IRUGO);

/*
 * module administration
 */
module_init(rpad_init);
module_exit(rpad_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Nils Roos <security@techno.ms>");
MODULE_DESCRIPTION("RedPitaya architecture driver");
