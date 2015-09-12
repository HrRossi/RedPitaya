/*
 * rp_asg.c
 *
 *  Created on: 8 Nov 2014
 *      Author: nils
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/types.h>
#include <linux/errno.h>
#include <linux/mm.h>
#include <linux/gfp.h>
#include <linux/slab.h>
#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <asm/uaccess.h>
#include <asm/io.h>

#include "rp_pl.h"
#include "rp_pl_hw.h"
#include "rp_asg.h"

/* asg registers */
#define ASG_control		0x00000000UL
#define ASG_a_amp_dc		0x00000004UL
#define ASG_a_size		0x00000008UL
#define ASG_a_ofs		0x0000000cUL
#define ASG_a_step		0x00000010UL
#define ASG_b_amp_dc		0x00000024UL
#define ASG_b_size		0x00000028UL
#define ASG_b_ofs		0x0000002cUL
#define ASG_b_step		0x00000030UL
/* DDR Slurp extension */
#define ASG_ddr_control		0x00000100UL
#define ASG_ddr_a_base		0x00000104UL
#define ASG_ddr_a_end		0x00000108UL
#define ASG_ddr_a_rdymx		0x0000010cUL
#define ASG_ddr_b_base		0x00000110UL
#define ASG_ddr_b_end		0x00000114UL
#define ASG_ddr_b_rdymx		0x00000118UL

static unsigned int ddrs_minsize = 0x00010000UL;
static unsigned int ddrs_maxsize = 0x00400000UL;

static void start_slurping(struct rpad_asg *asg);

/*
 * allocate asg-specific resources:
 * - DMA memory buffers
 */
static struct rpad_device *rpad_setup_asg(const struct rpad_device *dev_temp)
{
	struct rpad_asg *asg;
	/* FIXME dma_alloc_coherent with the device instead of get_free_pages ? */
	//dma_addr_t dma_handle;
	//void *cpu_addr;
	//size_t size;
	//struct device *dev = asg->rp_dev.dev;
	unsigned long cpu_addr;
	unsigned int size;

	asg = kzalloc(sizeof(struct rpad_asg), GFP_KERNEL);
	if (!asg)
		return ERR_PTR(-ENOMEM);

	asg->rp_dev = *dev_temp;

	//if (dma_set_coherent_mask(dev, DMA_BIT_MASK(32))) {
	//	printk(KERN_WARNING "rpad_asg: no suitable DMA available\n");
	//	return -ENOMEM;
	//}
	for (size = ddrs_maxsize; size >= ddrs_minsize; size >>= 1) {
		printk(KERN_INFO "rpad_asg: trying buffer size %x\n", size);
		//cpu_addr = dma_alloc_coherent(dev, size, &dma_handle, GFP_DMA);
		//if (!IS_ERR_OR_NULL(cpu_addr))
		//	break;
		cpu_addr = __get_free_pages(GFP_KERNEL,
		                            order_base_2(size >> PAGE_SHIFT));
		if (cpu_addr)
			break;
	}

	if (size < ddrs_minsize) {
		printk(KERN_WARNING "rpad_asg: not enough contiguous memory\n");
		return ERR_PTR(-ENOMEM);
	}

	asg->buffer_addr = cpu_addr;
	asg->buffer_size = size;
	//asg->buffer_phys_addr = dma_handle;
	asg->buffer_phys_addr = virt_to_phys((void *)cpu_addr); /* FIXME we're not supposed to use virt_to_phys */

	asg->ba_addr = asg->buffer_addr;
	asg->ba_size = asg->buffer_size / 2;
	asg->ba_phys_addr = asg->buffer_phys_addr;
	asg->ba_last_curr = 0UL;
	asg->bb_addr = asg->buffer_addr + asg->buffer_size / 2;
	asg->bb_size = asg->buffer_size / 2;
	asg->bb_phys_addr = asg->buffer_phys_addr + asg->buffer_size / 2;
	asg->bb_last_curr = 0UL;

	printk(KERN_INFO "rpad_asg: virt %p phys %p\n",
	       (void *)asg->buffer_addr, (void *)asg->buffer_phys_addr);

	return &asg->rp_dev;
}

/*
 * release asg-specific resources.
 */
static void rpad_teardown_asg(struct rpad_device *rp_dev)
{
	struct rpad_asg *asg =
		container_of(rp_dev, struct rpad_asg, rp_dev);

	//struct device *dev = asg->rp_dev.dev;
	//dma_free_coherent(dev, asg->buffer_size, asg->buffer_addr,
	//                  asg->buffer_phys_addr);
	free_pages(asg->buffer_addr,
	           order_base_2(asg->buffer_size >> PAGE_SHIFT));

	kfree(asg);
}

/*
 *
 */
static int init_hardware(struct rpad_asg *asg)
{
	unsigned int id;

	if (asg->hw_init_done)
		return 0;

	id = ioread32(rp_addr(asg, RPAD_SYS_ID));
	if (RPAD_VERSION(id) != 1)
		return -ENODEV; /* not a supported version */

	/* load buffer addresses */
	iowrite32(asg->ba_phys_addr, rp_addr(asg, ASG_ddr_a_base));
	iowrite32(asg->ba_phys_addr + asg->ba_size,
	          rp_addr(asg, ASG_ddr_a_end));
	iowrite32(asg->bb_phys_addr, rp_addr(asg, ASG_ddr_b_base));
	iowrite32(asg->bb_phys_addr + asg->bb_size,
	          rp_addr(asg, ASG_ddr_b_end));

	start_slurping(asg);

	asg->hw_init_done = 1;

	return 0;
}

/*
 * Starts reading. Doesn't check for version or hw_init_done.
 */
static void start_slurping(struct rpad_asg *asg)
{
	/* enable slurping on A/B */
	iowrite32(0x00000003, rp_addr(asg, ASG_ddr_control));
}

/*
 *
 */
static void stop_hardware(struct rpad_asg *asg)
{
	if (!asg->hw_init_done)
		return;

	iowrite32(0x00000000, rp_addr(asg, ASG_ddr_control));
	asg->hw_init_done = 0;
}

/*
 * specific operations done during open are still in flux
 *
 * initialize hardware
 */
static int rpad_asg_open(struct inode *inodp, struct file *filp)
{
	int retval = 0;
	struct rpad_asg *asg;

	asg = container_of(inodp->i_cdev, struct rpad_asg, rp_dev.cdev);
	filp->private_data = asg;

	if (mutex_lock_interruptible(&asg->rp_dev.mtx))
		return -ERESTARTSYS;

	retval = init_hardware(asg);

	mutex_unlock(&asg->rp_dev.mtx);

	return retval;
}

/*
 * specific operations done during release are still in flux
 *
 * stop asg, mark device uninitialized.
 */
static int rpad_asg_release(struct inode *inodp, struct file *filp)
{
	struct rpad_asg *asg = (struct rpad_asg *)filp->private_data;

	if (mutex_lock_interruptible(&asg->rp_dev.mtx))
		return -ERESTARTSYS;

	stop_hardware(asg);

	mutex_unlock(&asg->rp_dev.mtx);

	return 0;
}

/*
 * architectural glue to bind the right set of functions to the hardware
 */
static struct file_operations rpad_asg_fops = {
	.owner		= THIS_MODULE,
	.open		= rpad_asg_open,
	.release	= rpad_asg_release,
};

static struct rpad_devtype_data rpad_asg_data_v1 = {
	.type		= RPAD_ASG_TYPE,
	.setup		= rpad_setup_asg,
	.teardown	= rpad_teardown_asg,
	.fops		= &rpad_asg_fops,
	.iops		= NULL,
	.name		= "asg",
};

struct rpad_devtype_data *rpad_asg_provider(unsigned int version)
{
	switch (version) {
	case 1:
		return &rpad_asg_data_v1;
	default:
		return NULL;
	}
}

/*
 * supported parameters on the insmod command line
 */
module_param(ddrs_minsize, uint, S_IRUGO);
module_param(ddrs_maxsize, uint, S_IRUGO);
