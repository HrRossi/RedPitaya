/*
 * rp_pl_hw.c
 *
 *  Created on: 11 Oct 2014
 *      Author: nils
 */

#include <linux/kernel.h>
#include <linux/ioport.h>
#include <asm/string.h>
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
#define SYS_irq_tab	0x00000100UL /* one 32bit entry per sysbus region */

/*
 * this is the anchor for the recognized functional blocks. if your block
 * presents one of the defined enum rpad_devtype values as type in its SYS_ID
 * register, this table will be consulted to fetch a set of functions of your
 * choosing to handle the device, along with some other data.
 */
static devtype_provider_t rpad_devtype_table[NUM_RPAD_TYPES] = {
	[RPAD_HK_TYPE]		= rpad_hk_provider,
	[RPAD_SCOPE_TYPE]	= rpad_scope_provider,
	[RPAD_ASG_TYPE]		= rpad_asg_provider,
	/*[RPAD_PID_TYPE]		= rpad_pid_provider,*/
	/*[RPAD_AMS_TYPE]		= rpad_ams_provider,*/
	/*[RPAD_DAISY_TYPE]	= rpad_daisy_provider,*/
	/* add pointer to your devtype_provider_t function at the appropriate
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

	switch (RPAD_VERSION(sys->id)) {
	case 1:
	case 2:
		break;
	default:
		return 0; /* not a supported version */
	}

	return 1;
}

/*
 * access the region's SYS_ID register and look up and return the data for this
 * type and version through the provider from rpad_devtype_table. this fails if
 * the io memory region cannot be mapped or if the SYS_ID contains an invalid
 * type or an unsupported version.
 */
struct rpad_devtype_data *rpad_get_devtype_data(int region_nr,
                                                struct hw_config *hw)
{
	resource_size_t start = RPAD_PL_BASE + region_nr * RPAD_PL_REGION_SIZE;
	void __iomem *base;
	unsigned int type;
	unsigned int version;
	struct rpad_devtype_data *data;

	if (!request_mem_region(start, RPAD_PL_REGION_SIZE, "rpad_sysconfig"))
		return ERR_PTR(-EBUSY);

	base = ioremap_nocache(start, RPAD_PL_REGION_SIZE);
	if (!base) {
		release_mem_region(start, RPAD_PL_REGION_SIZE);
		return ERR_PTR(-EBUSY);
	}

	hw->id    = ioread32(base + RPAD_SYS_ID);
	hw->sys_1 = ioread32(base + RPAD_SYS_1);
	hw->sys_2 = ioread32(base + RPAD_SYS_2);
	hw->sys_3 = ioread32(base + RPAD_SYS_3);

	iounmap(base);
	release_mem_region(start, RPAD_PL_REGION_SIZE);

	type = RPAD_TYPE(hw->id);
	version = RPAD_VERSION(hw->id);

	if (type == RPAD_NO_TYPE || type >= NUM_RPAD_TYPES ||
	    !rpad_devtype_table[type] ||
	    !(data = rpad_devtype_table[type](version)))
		return ERR_PTR(-ENXIO);

	return data;
}

static int irq_id(unsigned int irq_nr) {
	if (irq_nr < 8)
		return 61 + irq_nr;
	else if (irq_nr < 16)
		return 84 + irq_nr - 8;
	else
		return 0;
}

/*
 * reads the interrupt configuration from the sysconfig IO region.
 */
void rpad_get_irq_config(struct rpad_sysconfig *sys, int region_nr,
                         struct rpad_irq_config *config)
{
	unsigned int config_word;

	memset(config, 0, sizeof(*config));

	config_word = ioread32(rp_sysa(sys, SYS_irq_tab + 4 * region_nr));

	if (config_word & 0x00080000U)
		config->irq0_id = irq_id((config_word & 0x0000f000U) >> 12);

	if (config_word & 0x00040000U)
		config->irq1_id = irq_id((config_word & 0x00000f00U) >> 8);

	if (config_word & 0x00020000U)
		config->irq2_id = irq_id((config_word & 0x000000f0U) >> 4);

	if (config_word & 0x00010000U)
		config->irq3_id = irq_id(config_word & 0x0000000fU);
}
