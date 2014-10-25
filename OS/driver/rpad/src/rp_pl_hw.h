/*
 * rp_pl_hw.h
 *
 *  Created on: 11 Oct 2014
 *      Author: nils
 */

#ifndef RP_PL_HW_H_
#define RP_PL_HW_H_

#include "linux/fs.h"
#include "rp_pl.h"
#include "rp_pl_dev.h"

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
	RPAD_NO_TYPE = 0,	/* when logic supplies no value, regs read 0 */
	RPAD_HK_TYPE,		/* 1 */
	RPAD_SCOPE_TYPE,	/* 2 */
	RPAD_ASG_TYPE,		/* 3 */
	RPAD_PID_TYPE,		/* 4 */
	RPAD_AMS_TYPE,		/* 5 */
	RPAD_DAISY_TYPE,	/* 6 */
	/* insert types for new logic blocks below, append ONLY */

	NUM_RPAD_TYPES,		/* new types only above this line */
	RPAD_SYS_TYPE = 0xfff
};

struct rpad_devtype_data {
	const enum rpad_devtype	type;
	struct rpad_device	*(*setup)(const struct rpad_device *);
	void			(*teardown)(struct rpad_device *);
	struct file_operations	*fops;
	void			*private;
	char			*name;
};

int rpad_check_sysconfig(struct rpad_sysconfig *sys);
struct rpad_devtype_data *rpad_get_devtype_data(int region_nr);

#endif /* RP_PL_HW_H_ */
