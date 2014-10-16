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

/*
 * the device structure is very much preliminary and guaranteed to change
 * substantially in order to accommodate enumerated subdevices etc. soonish
 *
 * sem                  access control
 * hw_init_done         initialited flag
 * buffer_addr          virtual address of DDR buffer
 * buffer_size          size of DDR buffer
 * buffer_phys_addr     physical address DDR buffer
 * crp                  current read position (virtual address)
 * buffer_end           last position of buffer (virtual address)
 * text_page            one page to prepare human readable output in
 * read_index           read offset into the text_page
 * max_index            end offset of prepared data in text_page
 * scope                resource pointer for our io allotment
 * scope_base           io cookie to use with ioread/iowrite/...
 * cdev                 character device anchor
 */
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

#define rp_scope(dev,u) ((void __iomem *)((dev)->scope_base + (u)))

#endif /* RP_PL_H_ */
