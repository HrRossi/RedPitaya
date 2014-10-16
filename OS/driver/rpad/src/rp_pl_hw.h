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

#define RPAD_HK_BASE  (RPAD_PL_BASE + 0 * RPAD_PL_SECTION_LENGTH)
#define RPAD_SCO_BASE (RPAD_PL_BASE + 1 * RPAD_PL_SECTION_LENGTH)
#define RPAD_ASG_BASE (RPAD_PL_BASE + 2 * RPAD_PL_SECTION_LENGTH)
#define RPAD_PID_BASE (RPAD_PL_BASE + 3 * RPAD_PL_SECTION_LENGTH)
#define RPAD_AMS_BASE (RPAD_PL_BASE + 4 * RPAD_PL_SECTION_LENGTH)
#define RPAD_DSY_BASE (RPAD_PL_BASE + 5 * RPAD_PL_SECTION_LENGTH)

/* common to all recognized blocks - in fact, these facilitate detection */
#define RPAD_SYS_ID       0x00000ff0UL
#define RPAD_SYS_1        0x00000ff4UL
#define RPAD_SYS_2        0x00000ff8UL
#define RPAD_SYS_3        0x00000ffcUL

/* scope registers */
#define SCOPE_ctrl        0x00000000UL
#define SCOPE_trig_src    0x00000004UL
#define SCOPE_a_tresh     0x00000008UL
#define SCOPE_b_tresh     0x0000000cUL
#define SCOPE_dly         0x00000010UL
#define SCOPE_dec         0x00000014UL
#define SCOPE_wp_cur      0x00000018UL
#define SCOPE_wp_trig     0x0000001cUL
#define SCOPE_a_hyst      0x00000020UL
#define SCOPE_b_hyst      0x00000024UL
#define SCOPE_avg_en      0x00000028UL
#define SCOPE_a_filt_aa   0x00000030UL
#define SCOPE_a_filt_bb   0x00000034UL
#define SCOPE_a_filt_kk   0x00000038UL
#define SCOPE_a_filt_pp   0x0000003cUL
#define SCOPE_b_filt_aa   0x00000040UL
#define SCOPE_b_filt_bb   0x00000044UL
#define SCOPE_b_filt_kk   0x00000048UL
#define SCOPE_b_filt_pp   0x0000004cUL
#define SCOPE_ddr_control 0x00000100UL
#define SCOPE_ddr_a_base  0x00000104UL
#define SCOPE_ddr_a_end   0x00000108UL
#define SCOPE_ddr_b_base  0x0000010cUL
#define SCOPE_ddr_b_end   0x00000110UL
#define SCOPE_ddr_a_curr  0x00000114UL
#define SCOPE_ddr_b_curr  0x00000118UL

void test_hardware(struct rpad_device *dev);

#endif /* RP_PL_HW_H_ */
