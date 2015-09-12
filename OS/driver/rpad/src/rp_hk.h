/*
 * rp_hk.h
 *
 *  Created on: 18 Oct 2014
 *      Author: nils
 */

#ifndef RP_HK_H_
#define RP_HK_H_

#include "rp_pl.h"
#include "rp_pl_hw.h"

/*
 * rp_dev	embedded rpad_device
 */
struct rpad_hk {
	struct rpad_device	rp_dev;
};

/* referenced from rp_pl_hw.c to put into the devtype_data table (see there) */
struct rpad_devtype_data *rpad_hk_provider(unsigned int version);

#endif /* RP_HK_H_ */
