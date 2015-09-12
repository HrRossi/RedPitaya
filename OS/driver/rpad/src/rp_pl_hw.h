/*
 * rp_pl_hw.h
 *
 *  Created on: 11 Oct 2014
 *      Author: nils
 */

#ifndef RP_PL_HW_H_
#define RP_PL_HW_H_

#include <linux/fs.h>
#include <linux/interrupt.h>

#include "rp_pl.h"

#define RPAD_VERSIONBITS	20
#define RPAD_VERSIONMASK	((1U << RPAD_VERSIONBITS) - 1)

#define RPAD_TYPE(id)		((unsigned int)((id) >> RPAD_VERSIONBITS))
#define RPAD_VERSION(id)	((unsigned int)((id) & RPAD_VERSIONMASK))
#define MKRPAD_ID(typ,ver)	(((typ) << RPAD_VERSIONBITS) | (ver))

/* address range and granularity of the RedPitaya PL internal system bus */
#define RPAD_PL_BASE		0x40000000UL /* address range that is mapped  */
#define RPAD_PL_END		0x80000000UL /* to AXI_GP0                    */
#define RPAD_PL_REGION_SIZE	0x00100000UL /* size of one system bus region */
#define RPAD_PL_SYS_RESERVED	0x7fff0000UL /* reserved region for sysconfig */

/* common to all recognized blocks - in fact, these facilitate recognition */
#define RPAD_SYS_ID	0x00000ff0UL
#define RPAD_SYS_1	0x00000ff4UL
#define RPAD_SYS_2	0x00000ff8UL
#define RPAD_SYS_3	0x00000ffcUL

/*
 * device types - these go into the upper (32-RPAD_VERSIONBITS) bits of the
 * RPAD_SYS_ID register of each PL logic block
 */
enum rpad_devtype {
	RPAD_NO_TYPE = 0,	/* when logic supplies no value, io reads 0 */
	RPAD_HK_TYPE,		/* 0x001 */
	RPAD_SCOPE_TYPE,	/* 0x002 */
	RPAD_ASG_TYPE,		/* 0x003 */
	RPAD_PID_TYPE,		/* 0x004 */
	RPAD_AMS_TYPE,		/* 0x005 */
	RPAD_DAISY_TYPE,	/* 0x006 */
	/* insert types for new logic blocks below, append ONLY */

	NUM_RPAD_TYPES,		/* new types only above this line */
	RPAD_SYS_TYPE = 0xfff
};

/*
 * device specific data relevant to architecture management
 * type		type of device this data is applicable to
 * setup	device initialisation function. needs at least to allocate its
 * 		device struct, copy the contents of dev_temp into it and return
 * 		a pointer to it. must not retain a reference to dev_temp.
 * teardown	device shutdown function. needs at least to reverse the device
 * 		struct allocation.
 * fops		file operations supported by the device
 * iops		interrupt handlers of the device
 * private	private data
 * name		component name, like "scope". full name would be "rpad_scope%d"
 */
struct rpad_devtype_data {
	const enum rpad_devtype	type;
	struct rpad_device	*(*setup)(const struct rpad_device *dev_temp);
	void			(*teardown)(struct rpad_device *rp_dev);
	struct file_operations	*fops;
	struct irq_handlers	*iops;
	void			*private;
	char			*name;
};

/*
 * device specific irq configuration
 * irq[0..3]_id	GIC interrupt ID for interrupt requests 0-3 of the respective
 * 		sysbus block. 0 denotes no irq connection. the purpose of all
 * 		configured irqs is device specific.
 */
struct rpad_irq_config {
	int	irq0_id;
	int	irq1_id;
	int	irq2_id;
	int	irq3_id;
};

/*
 * ...
 */
struct irq_handlers {
	irq_handler_t	irq0_handler;
	irq_handler_t	irq1_handler;
	irq_handler_t	irq2_handler;
	irq_handler_t	irq3_handler;
};

typedef struct rpad_devtype_data *(*devtype_provider_t)(unsigned int version);

int rpad_check_sysconfig(struct rpad_sysconfig *sys);
struct rpad_devtype_data *rpad_get_devtype_data(int region_nr,
                                                struct hw_config *hw);
void rpad_get_irq_config(struct rpad_sysconfig *sys, int region_nr,
                         struct rpad_irq_config *config);

#endif /* RP_PL_HW_H_ */
