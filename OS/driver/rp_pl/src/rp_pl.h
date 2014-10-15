/*
 * rp_pl.h
 *
 *  Created on: 29 Sep 2014
 *      Author: nils
 */

#ifndef RP_PL_H_
#define RP_PL_H_

#include <linux/cdev.h>
#include <linux/semaphore.h>
#include <asm/io.h>

struct rpad_device {
	struct semaphore sem;
	int hw_init_done;
	unsigned long buffer_addr;
	unsigned int buffer_size;
	unsigned long buffer_phys_addr;
	unsigned long crp;
	unsigned long buffer_end;
	char *text_page;
	int read_index;
	int max_index;
	struct resource *scope;
	void __iomem *scope_base;
	struct cdev cdev;
};

#define rp_adc_reg(dev,u) ((void __iomem *)((dev)->scope_base + (u)))

#endif /* RP_PL_H_ */
