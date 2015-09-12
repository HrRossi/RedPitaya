/*
 * rp_hk.c
 *
 *  Created on: 18 Oct 2014
 *      Author: nils
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <linux/errno.h>
#include <linux/fs.h>
#include <linux/mm.h>
#include <linux/gfp.h>
#include <linux/slab.h>

#include "rp_pl.h"
#include "rp_pl_hw.h"
#include "rp_hk.h"

/* hk registers */
#define HK_id_value		0x00000000UL
#define HK_dna_value_l		0x00000004UL
#define HK_dna_value_h		0x00000008UL
#define HK_exp_p_dir_o		0x00000010UL
#define HK_exp_n_dir_o		0x00000014UL
#define HK_exp_p_dat_o		0x00000018UL
#define HK_exp_n_dat_o		0x0000001cUL
#define HK_exp_p_dat_i		0x00000020UL
#define HK_exp_n_dat_i		0x00000024UL
#define HK_led_reg		0x00000030UL

static struct rpad_device *rpad_setup_hk(const struct rpad_device *dev_temp)
{
	struct rpad_hk *hk;

	hk = kzalloc(sizeof(*hk), GFP_KERNEL);
	if (!hk)
		return ERR_PTR(-ENOMEM);

	hk->rp_dev = *dev_temp;

	/* TODO */

	return &hk->rp_dev;
}

static void rpad_teardown_hk(struct rpad_device *rp_dev)
{
	struct rpad_hk *hk = container_of(rp_dev, struct rpad_hk, rp_dev);

	kfree(hk);
}

static const struct vm_operations_struct rpad_hk_mmap_mem_ops = {
};

/*
 * create mapping for IO range of housekeeping, derived from dev/mem code
 */
static int rpad_hk_mmap(struct file *filp, struct vm_area_struct *vma)
{
	struct rpad_hk *scope = (struct rpad_hk *)filp->private_data;
	size_t size = vma->vm_end - vma->vm_start;
	resource_size_t addr = vma->vm_pgoff << PAGE_SHIFT;

	if (addr        < scope->rp_dev.sys_addr ||
	    addr + size > scope->rp_dev.sys_addr + RPAD_PL_REGION_SIZE)
		return -EINVAL;

	vma->vm_page_prot = phys_mem_access_prot(filp, vma->vm_pgoff, size,
	                                         vma->vm_page_prot);

	vma->vm_ops = &rpad_hk_mmap_mem_ops;

	/* Remap-pfn-range will mark the range VM_IO */
	if (remap_pfn_range(vma, vma->vm_start, vma->vm_pgoff, size,
	                    vma->vm_page_prot))
		return -EAGAIN;

	return 0;
}

/*
 * architectural glue to bind the right set of functions to the hardware
 */
static struct file_operations rpad_hk_fops = {
	.owner		= THIS_MODULE,
	.mmap		= rpad_hk_mmap,
};

static struct rpad_devtype_data rpad_hk_data_v1 = {
	.type		= RPAD_HK_TYPE,
	.setup		= rpad_setup_hk,
	.teardown	= rpad_teardown_hk,
	.fops		= &rpad_hk_fops,
	.iops		= NULL,
	.name		= "hk",
};

struct rpad_devtype_data *rpad_hk_provider(unsigned int version)
{
	switch (version) {
	case 1:
		return &rpad_hk_data_v1;
	default:
		return NULL;
	}
}
