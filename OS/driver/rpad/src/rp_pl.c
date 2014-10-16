/*
 * rp_pl.c
 *
 *  Created on: 26 Sep 2014
 *      Author: nils
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>
#include <linux/types.h>
#include <linux/mm_types.h>
#include <linux/errno.h>
#include <linux/device.h>
#include <linux/cdev.h>
#include <linux/dma-mapping.h>
#include <linux/stat.h>
#include <linux/fs.h>
#include <linux/gfp.h>
#include <linux/slab.h>
#include <linux/ioport.h>
#include <asm/io.h>
#include <asm/uaccess.h>

#include "rp_pl_hw.h"
#include "rp_pl_dev.h"
#include "rp_pl.h"


static size_t rpad_minsize = 0x00010000;
static size_t rpad_maxsize = 0x00400000;
static unsigned int rpad_major = 0;
static unsigned int rpad_minor = 0;

static struct rpad_device rpad_dev;

static int rpad_open(struct inode *, struct file *);
static int rpad_release(struct inode *, struct file *);
static ssize_t rpad_read(struct file *, char __user *, size_t, loff_t *);
static ssize_t rpad_write(struct file *, const char __user *, size_t, loff_t *);
static int rpad_mmap(struct file *, struct vm_area_struct *);

static struct file_operations rpad_fops = {
	.owner   = THIS_MODULE,
	.open    = rpad_open,
	.release = rpad_release,
	.read    = rpad_read,
	.write   = rpad_write,
	.mmap    = rpad_mmap,
};

/*
 * fills the text_page with fresh human readable data from the DDR buffer
 */
static size_t prepare_output_buffer(struct rpad_device *dev)
{
	int write_index;

	if (dev->crp >= dev->buffer_end)
		return 0;

	for (write_index = 0; write_index < PAGE_SIZE - 1; write_index += 8) {
		if (unlikely(dev->crp >= dev->buffer_end))
			break;

		sprintf(&dev->text_page[write_index],"   %04x\n",
		        *((u16 *)(dev->crp)));
		dev->crp += 2;
	}
	dev->read_index = 0;
	dev->max_index = write_index;

	return write_index;
}

/*
 * specific operations done during open are still in flux
 *
 * initializes hardware and allocates text_page, if not already done. resets
 * the singular current read pointer und prepares the first batch of data.
 */
static int rpad_open(struct inode *inodp, struct file *filp)
{
	int retval = 0;
	struct rpad_device *dev;

	dev = container_of(inodp->i_cdev, struct rpad_device, cdev);
	filp->private_data = dev;

	if (down_interruptible(&dev->sem))
		return -ERESTARTSYS;

	if (!dev->hw_init_done) {
		dev->text_page = (char *)get_zeroed_page(GFP_KERNEL);
		if (!dev->text_page) {
			retval = -ENOMEM;
			goto out;
		}

		test_hardware(dev);
		dev->buffer_end = dev->buffer_addr + dev->buffer_size;

		dev->hw_init_done = 1;
	}

	dev->crp = dev->buffer_addr;
	dev->read_index = PAGE_SIZE;
	prepare_output_buffer(dev);

out:
	up(&dev->sem);

	return retval;
}

/*
 * specific operations done during release are still in flux
 *
 * frees text_page, marks device uninitialized.
 */
static int rpad_release(struct inode *inodp, struct file *filp)
{
	struct rpad_device *dev = (struct rpad_device *)filp->private_data;

	if (down_interruptible(&dev->sem))
		return -ERESTARTSYS;

	if (dev->hw_init_done) {
		free_page((unsigned long)dev->text_page);
		dev->hw_init_done = 0;
	}

	up(&dev->sem);

	return 0;
}

/*
 * specific operations done during read are still in flux
 *
 * feeds the unread part of text_page to userspace, attempts to refill the page
 * if it is currently fully read. no heed is given to the file offset, every
 * read gets data from the singular, ever progressing current read position.
 * (meaning, you will get all channel A data first and then all channel B data)
 */
static ssize_t rpad_read(struct file *filp, char __user *ubuf, size_t usize, loff_t *uoffp)
{
	ssize_t length;
	struct rpad_device *dev = (struct rpad_device *)filp->private_data;

	if (down_interruptible(&dev->sem))
		return -ERESTARTSYS;

	length = dev->max_index - dev->read_index;
	if (length <= 0 || dev->read_index < 0)
		length = prepare_output_buffer(dev);
	if (length == 0)
		goto out;

	if ((size_t)length > usize)
		length = usize;

	if (copy_to_user(ubuf, &dev->text_page[dev->read_index], length)) {
		length = -EFAULT;
		goto out;
	}
	dev->read_index += length;
	*uoffp += length;

out:
	up(&dev->sem);

	return length;
}

static ssize_t rpad_write(struct file *filp, const char __user *ubuf, size_t usize, loff_t *uoffp)
{
	// TODO
	return -EINVAL;
}

static int rpad_mmap(struct file *filp, struct vm_area_struct *vma)
{
	// TODO
	return -EINVAL;
}

/*
 * allocates memory buffers and io address blocks
 */
static int rpad_resources_alloc(struct rpad_device *dev)
{
	// FIXME dma_alloc_coherent mit ordentlichem device ?
	//dma_addr_t dma_handle;
	//void *cpu_addr;
	//size_t size;
	//struct device *dev;
	unsigned long cpu_addr;
	unsigned int size;

	dev->hw_init_done = 0;

	//if (dma_set_coherent_mask(dev, DMA_BIT_MASK(32))) {
	//	printk(KERN_WARNING "rpad: no suitable DMA available\n");
	//	return -ENOMEM;
	//}

	for (size = rpad_maxsize; size >= rpad_minsize; size >>= 1) {
		printk(KERN_ALERT "rpad: trying buffer size %x\n", size);
		//cpu_addr = dma_alloc_coherent(dev, size, &dma_handle, GFP_DMA);
		//if (!IS_ERR_OR_NULL(cpu_addr))
		//	break;
		cpu_addr = __get_free_pages(GFP_KERNEL,
		                            order_base_2(size >> PAGE_SHIFT));
		if (cpu_addr)
			break;
	}
	if (size < rpad_minsize) {
		printk(KERN_WARNING "rpad: not enough contiguous memory\n");
		return -ENOMEM;
	}

	dev->buffer_addr = cpu_addr;
	dev->buffer_size = size;
	//dev->buffer_phys_addr = dma_handle;
	dev->buffer_phys_addr = virt_to_phys((void *)cpu_addr); // FIXME we're not supposed to use virt_to_phys

	printk(KERN_ALERT "rpad: virt %p\n", (void *)dev->buffer_addr);
	printk(KERN_ALERT "rpad: phys %p\n", (void *)dev->buffer_phys_addr);

	dev->scope = request_mem_region(RPAD_SCO_BASE, RPAD_PL_SECTION_LENGTH,
	                                "rpad_scope");
	if (!dev->scope)
		goto error_free;

	dev->scope_base = ioremap_nocache(RPAD_SCO_BASE, RPAD_PL_SECTION_LENGTH);
	if (!dev->scope_base)
		goto error_rel;

	sema_init(&dev->sem, 1);

	return 0;

error_rel:
	release_mem_region(RPAD_SCO_BASE, RPAD_PL_SECTION_LENGTH);
error_free:
	free_pages(cpu_addr, order_base_2(size >> PAGE_SHIFT));

	return -EBUSY;
}

/*
 * frees all allocated memory buffers and io address blocks
 */
static inline void rpad_resources_free(struct rpad_device *dev)
{
	iounmap(dev->scope_base);
	release_mem_region(RPAD_SCO_BASE, RPAD_PL_SECTION_LENGTH);

	//dma_free_coherent(dev, size, cpu_addr, dma_handle);
	free_pages(dev->buffer_addr,
	           order_base_2(dev->buffer_size >> PAGE_SHIFT));
}

/*
 * requisitions the major/minor device number(s) given through module params
 */
static int rpad_device_register(struct rpad_device *dev)
{
	int ret;
	dev_t devt;

	if (rpad_major) {
		devt = MKDEV(rpad_major, rpad_minor);
		ret = register_chrdev_region(devt, RPAD_CHANNELS, "rpad");
	} else {
		ret = alloc_chrdev_region(&devt, rpad_minor, RPAD_CHANNELS, "rpad");
	}
	if (ret < 0) {
		printk(KERN_WARNING
		       "rpad: can't get major %d\n", rpad_major);
		return ret;
	}
	rpad_major = MAJOR(devt);

	if (RPAD_CHANNELS > 1)
		printk(KERN_ALERT "rpad: registered as %u:%u-%u\n",
		       rpad_major, rpad_minor, rpad_minor + RPAD_CHANNELS - 1);
	else
		printk(KERN_ALERT "rpad: registered as %u:%u\n",
		       rpad_major, rpad_minor);

	return 0;
}

/*
 * releases the major/minor device number(s)
 */
static inline void rpad_device_unregister(void)
{
	unregister_chrdev_region(MKDEV(rpad_major, rpad_minor), RPAD_CHANNELS);
}

/*
 * registers the module's components (device, class, char device) with the
 * kernel
 */
static int rpad_device_activate(struct rpad_device *dev)
{
	int ret;

	ret = rpad_setup_device_class();
	if (ret) {
		printk(KERN_ALERT "rpad: class setup error\n");
		return ret;
	}
	ret = rpad_setup_device(NULL, MKDEV(rpad_major, rpad_minor));
	if (ret) {
		rpad_release_device_class();
		printk(KERN_ALERT "rpad: device setup error\n");
		return ret;
	}

	cdev_init(&dev->cdev, &rpad_fops);
	dev->cdev.owner = THIS_MODULE;

	ret = cdev_add(&dev->cdev, MKDEV(rpad_major, rpad_minor), RPAD_CHANNELS);
	if (ret) {
		rpad_release_device(MKDEV(rpad_major, rpad_minor));
		rpad_release_device_class();
		printk(KERN_WARNING "rpad: can't add char device\n");
		return ret;
	}

	return 0;
}

/*
 * detaches the module's components (device, class, char device) from the kernel
 */
static inline void rpad_device_deactivate(struct rpad_device *dev)
{
	cdev_del(&dev->cdev);
	rpad_release_device(MKDEV(rpad_major, rpad_minor));
	rpad_release_device_class();
}

static int __init rpad_init(void)
{
	int ret;

	printk(KERN_ALERT "Module rpad loading\n");

	ret = rpad_device_register(&rpad_dev);
	if (ret)
		goto error_msg;

	ret = rpad_resources_alloc(&rpad_dev);
	if (ret)
		goto error_unreg;

	ret = rpad_device_activate(&rpad_dev);
	if (ret)
		goto error_free;

	printk(KERN_ALERT "Module rpad loaded\n");

	return 0;

error_free:
	rpad_resources_free(&rpad_dev);
error_unreg:
	rpad_device_unregister();
error_msg:
	printk(KERN_ALERT "Module rpad not loaded\n");

	return ret;
}

static void __exit rpad_exit(void)
{
	printk(KERN_ALERT "Module rpad unloading\n");

	rpad_device_deactivate(&rpad_dev);
	rpad_resources_free(&rpad_dev);
	rpad_device_unregister();

	printk(KERN_ALERT "Module rpad unloaded\n");
}

module_init(rpad_init);
module_exit(rpad_exit);

module_param(rpad_major, uint, S_IRUGO);
module_param(rpad_minor, uint, S_IRUGO);
module_param(rpad_minsize, uint, S_IRUGO);
module_param(rpad_maxsize, uint, S_IRUGO);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Nils Roos");
MODULE_DESCRIPTION("RedPitaya architecture driver");
