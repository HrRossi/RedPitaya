/*
 * rp_asg.h
 *
 *  Created on: 8 Nov 2014
 *      Author: nils
 */

#ifndef RP_ASG_H_
#define RP_ASG_H_

#include "rp_pl.h"
#include "rp_pl_hw.h"

/*
 * rp_dev		embedded rpad_device
 * hw_init_done		...
 * buffer_addr		virtual address of DDR buffer
 * buffer_size		size of DDR buffer
 * buffer_phys_addr	physical address DDR buffer
 * ...
 */
struct rpad_asg {
	struct rpad_device	rp_dev;
	int			hw_init_done;
	unsigned long		buffer_addr;
	unsigned int		buffer_size;
	unsigned long		buffer_phys_addr;
	unsigned long		ba_addr;
	unsigned int		ba_size;
	unsigned long		ba_phys_addr;
	unsigned long		ba_last_curr;
	unsigned long		bb_addr;
	unsigned int		bb_size;
	unsigned long		bb_phys_addr;
	unsigned long		bb_last_curr;
};

/* referenced from rp_pl_hw.c to put into the devtype_data table (see there) */
struct rpad_devtype_data *rpad_asg_provider(unsigned int version);

#endif /* RP_ASG_H_ */
