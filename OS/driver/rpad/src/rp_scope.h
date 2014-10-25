/*
 * rp_scope.h
 *
 *  Created on: 18 Oct 2014
 *      Author: nils
 */

#ifndef RP_SCOPE_H_
#define RP_SCOPE_H_

#include "rp_pl.h"
#include "rp_pl_hw.h"

/*
 * rp_dev		embedded rpad_device
 * hw_init_done		...
 * buffer_addr		virtual address of DDR buffer
 * buffer_size		size of DDR buffer
 * buffer_phys_addr	physical address DDR buffer
 * crp			current read position (virtual address)
 * buffer_end		last position of buffer (virtual address)
 * text_page		one page to prepare human readable output in
 * read_index		read offset into the text_page
 * max_index		end offset of prepared data in text_page
 */
struct rpad_scope {
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
extern struct rpad_devtype_data rpad_scope_data;

#endif /* RP_SCOPE_H_ */
