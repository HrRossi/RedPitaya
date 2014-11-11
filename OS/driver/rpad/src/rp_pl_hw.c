/*
 * rp_pl_hw.c
 *
 *  Created on: 11 Oct 2014
 *      Author: nils
 */

#include <linux/kernel.h>
#include <linux/ioport.h>
#include <asm/io.h>

#include "rp_pl.h"
#include "rp_pl_hw.h"
#include "rp_hk.h"
#include "rp_scope.h"
#include "rp_asg.h"
/*#include "rp_pid.h"*/
/*#include "rp_ams.h"*/
/*#include "rp_daisy.h"*/

/* sysconfig registers */
#define SYS_id		0x00000000UL
#define SYS_regions	0x00000004UL

/*
 * this is the anchor for the recognized functional blocks. if your block
 * presents one of the defined enum rpad_devtype values as type in its SYS_ID
 * register, this table will be consulted to fetch a set of functions of your
 * choosing to handle the device, along with some other data.
 */
static struct rpad_devtype_data *rpad_devtype_table[NUM_RPAD_TYPES] = {
	[RPAD_HK_TYPE]		= &rpad_hk_data,
	[RPAD_SCOPE_TYPE]	= &rpad_scope_data,
	[RPAD_ASG_TYPE]		= &rpad_asg_data,
	/*[RPAD_PID_TYPE]		= &rpad_pid_data,*/
	/*[RPAD_AMS_TYPE]		= &rpad_ams_data,*/
	/*[RPAD_DAISY_TYPE]	= &rpad_daisy_data,*/
	/* add pointer to your struct rpad_devtype_data at the appropriate
	 * enum const slot here. not using enum is discouraged. */
};

/*
 * check if the PL can be identified as a supported RPAD configuration.
 * can be called after sysconfig IO region is mapped.
 */
int rpad_check_sysconfig(struct rpad_sysconfig *sys)
{
	sys->id            = ioread32(rp_sysa(sys, SYS_id));
	sys->nr_of_regions = ioread32(rp_sysa(sys, SYS_regions));
	/* TODO perhaps also use some checksum or magic nr */

	if (RPAD_TYPE(sys->id) != RPAD_SYS_TYPE ||
	    sys->nr_of_regions <= 0 || sys->nr_of_regions > 1023)
		return 0; /* apparently not RPAD PL */

	if (RPAD_VERSION(sys->id) != 1)
		return 0; /* not a supported version */

	return 1;
}

/*
 * access the region's SYS_ID register and look up and return the type's data in
 * rpad_devtype_table. this fails if the io memory region cannot be mapped or if
 * the SYS_ID contains an invalid type.
 */
struct rpad_devtype_data *rpad_get_devtype_data(int region_nr)
{
	resource_size_t start = RPAD_PL_BASE + region_nr * RPAD_PL_REGION_SIZE;
	void __iomem *base;
	unsigned int type;

	if (!request_mem_region(start, RPAD_PL_REGION_SIZE, "rpad_sysconfig"))
		return ERR_PTR(-EBUSY);

	base = ioremap_nocache(start, RPAD_PL_REGION_SIZE);
	if (!base) {
		release_mem_region(start, RPAD_PL_REGION_SIZE);
		return ERR_PTR(-EBUSY);
	}

	type = RPAD_TYPE(ioread32(base + RPAD_SYS_ID));

	iounmap(base);
	release_mem_region(start, RPAD_PL_REGION_SIZE);

	if (type == RPAD_NO_TYPE || type >= NUM_RPAD_TYPES ||
	    !rpad_devtype_table[type])
		return ERR_PTR(-ENXIO);

	return rpad_devtype_table[type];
}
