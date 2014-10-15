/*
 * rp_pl_hw.h
 *
 *  Created on: 11 Oct 2014
 *      Author: nils
 */

#ifndef RP_PL_HW_H_
#define RP_PL_HW_H_

#include "rp_pl.h"

#define RPAD_CHANNELS 1

#define RPAD_PL_BASE 0x40000000UL
#define RPAD_PL_SECTION_LENGTH 0x00100000UL
#define RPAD_ADC_BASE (RPAD_PL_BASE + 1 * RPAD_PL_SECTION_LENGTH)

#define RPAD_ADC_ctrl        0x00000000UL
#define RPAD_ADC_trig_src    0x00000004UL
#define RPAD_ADC_a_tresh     0x00000008UL
#define RPAD_ADC_b_tresh     0x0000000cUL
#define RPAD_ADC_dly         0x00000010UL
#define RPAD_ADC_dec         0x00000014UL
#define RPAD_ADC_wp_cur      0x00000018UL
#define RPAD_ADC_wp_trig     0x0000001cUL
#define RPAD_ADC_a_hyst      0x00000020UL
#define RPAD_ADC_b_hyst      0x00000024UL
#define RPAD_ADC_avg_en      0x00000028UL
#define RPAD_ADC_a_filt_aa   0x00000030UL
#define RPAD_ADC_a_filt_bb   0x00000034UL
#define RPAD_ADC_a_filt_kk   0x00000038UL
#define RPAD_ADC_a_filt_pp   0x0000003cUL
#define RPAD_ADC_b_filt_aa   0x00000040UL
#define RPAD_ADC_b_filt_bb   0x00000044UL
#define RPAD_ADC_b_filt_kk   0x00000048UL
#define RPAD_ADC_b_filt_pp   0x0000004cUL
#define RPAD_ADC_ddr_a_base  0x00000060UL
#define RPAD_ADC_ddr_a_end   0x00000064UL
#define RPAD_ADC_ddr_b_base  0x00000068UL
#define RPAD_ADC_ddr_b_end   0x0000006cUL
#define RPAD_ADC_ddr_control 0x00000070UL
#define RPAD_ADC_ddr_a_curr  0x00000074UL
#define RPAD_ADC_ddr_b_curr  0x00000078UL

#define RPAD_ADC_test        0x00000FFCUL

void test_hardware(struct rpad_device *dev);

#endif /* RP_PL_HW_H_ */
