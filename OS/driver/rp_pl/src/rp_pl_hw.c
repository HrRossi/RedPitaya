/*
 * rp_pl_hw.c
 *
 *  Created on: 11 Oct 2014
 *      Author: nils
 */

#include <linux/kernel.h>
#include <linux/delay.h>
#include <asm/io.h>

#include "rp_pl.h"
#include "rp_pl_hw.h"

void test_hardware(struct rpad_device *dev)
{
	unsigned int test_a, test_b;

	test_a = ioread32(rp_adc_reg(dev, RPAD_ADC_test));
	printk(KERN_ALERT "rp_adc2ddr: ID %x\n", test_a);

	iowrite32(0x00000002, rp_adc_reg(dev, RPAD_ADC_ctrl)); // reset
	iowrite32(8, rp_adc_reg(dev, RPAD_ADC_dec));
	iowrite32(1, rp_adc_reg(dev, RPAD_ADC_avg_en));
	// TODO adc setup ?

	iowrite32(dev->buffer_phys_addr,
	          rp_adc_reg(dev, RPAD_ADC_ddr_a_base));
	iowrite32(dev->buffer_phys_addr + dev->buffer_size / 2,
	          rp_adc_reg(dev, RPAD_ADC_ddr_a_end));
	iowrite32(dev->buffer_phys_addr + dev->buffer_size / 2,
	          rp_adc_reg(dev, RPAD_ADC_ddr_b_base));
	iowrite32(dev->buffer_phys_addr + dev->buffer_size,
	          rp_adc_reg(dev, RPAD_ADC_ddr_b_end));
	iowrite32(0x0000000c, rp_adc_reg(dev, RPAD_ADC_ddr_control)); // reload A/B
	udelay(5);

	test_a = ioread32(rp_adc_reg(dev, RPAD_ADC_ddr_a_base));
	test_b = ioread32(rp_adc_reg(dev, RPAD_ADC_ddr_a_end));
	printk(KERN_ALERT "rp_adc2ddr: A %p - %p\n", (void *)test_a, (void *)test_b);
	test_a = ioread32(rp_adc_reg(dev, RPAD_ADC_ddr_b_base));
	test_b = ioread32(rp_adc_reg(dev, RPAD_ADC_ddr_b_end));
	printk(KERN_ALERT "rp_adc2ddr: B %p - %p\n", (void *)test_a, (void *)test_b);

	iowrite32(0x00000003, rp_adc_reg(dev, RPAD_ADC_ddr_control)); // enable A/B
	iowrite32(0x00000001, rp_adc_reg(dev, RPAD_ADC_ctrl)); // arm

	test_b = dev->buffer_phys_addr + dev->buffer_size / 2 - 0x00004000;
	do {
		test_a = ioread32(rp_adc_reg(dev, RPAD_ADC_ddr_a_curr));
	} while (test_a < test_b);

	iowrite32(0x00000002, rp_adc_reg(dev, RPAD_ADC_ctrl)); // reset
	iowrite32(0x00000000, rp_adc_reg(dev, RPAD_ADC_ddr_control));
	printk(KERN_ALERT "rp_adc2ddr: acquisition complete\n");
}
