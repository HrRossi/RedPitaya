/*
 * rp_scope.h
 *
 *  Created on: 18 Oct 2014
 *      Author: nils
 */

#ifndef RP_SCOPE_H_
#define RP_SCOPE_H_

#define RPAD_SCOPE_CHA_BUF	0x00000000
#define RPAD_SCOPE_CHB_BUF	0x00200000


#ifdef __KERNEL__

#include "rp_pl.h"
#include "rp_pl_hw.h"

/*
 * rp_dev		embedded rpad_device
 * hw_init_done		...
 * resched		timeout to schedule for awaiting new data
 * buffer_addr		virtual address of DDR buffer
 * buffer_size		size of DDR buffer
 * buffer_phys_addr	physical address DDR buffer
 * ...
 */
struct rpad_scope {
	struct rpad_device	rp_dev;
	int			hw_init_done;
	signed long		resched;
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
struct rpad_devtype_data *rpad_scope_provider(unsigned int version);

#endif /* __KERNEL__ */

#endif /* RP_SCOPE_H_ */
