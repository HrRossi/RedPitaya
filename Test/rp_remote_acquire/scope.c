/*
 * scope.c
 *
 *  Created on: 26 Oct 2014
 *      Author: nils
 *
 * The MIT License (MIT)
 *
 * Copyright (c) 2014 bkinman, Nils Roos
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <rp_scope.h>

#include "options.h"
#include "scope.h"

int scope_init(struct scope_parameter *param, option_fields_t *options)
{
	off_t buf_a_addr, buf_b_addr;
	int decimation = options->scope_dec;

	memset(param, 0, sizeof(*param));

	param->channel = options->scope_chn;
	param->scope_fd = open("/dev/rpad_scope0", O_RDWR);
	if (param->scope_fd < 0) {
		fprintf(stderr, "open scope failed, %d\n", errno);
		return -1;
	}

	param->mapped_io = mmap(NULL, 0x00100000UL, PROT_WRITE | PROT_READ,
	                        MAP_SHARED, param->scope_fd, 0x40100000UL);
	if (param->mapped_io == MAP_FAILED) {
		fprintf(stderr, "mmap scope io failed (non-fatal), %d\n",
		        errno);
		param->mapped_io = NULL;
	}

	if (param->channel == 0 || param->channel == 2) {
		/* TODO get phys addr and size from sysfs */
		param->buf_a_size = 0x00200000;
		buf_a_addr = RPAD_SCOPE_CHA_BUF;
		param->mapped_buf_a = mmap(NULL, param->buf_a_size, PROT_READ,
		                           MAP_SHARED, param->scope_fd,
		                           buf_a_addr);
		if (param->mapped_buf_a == MAP_FAILED) {
			fprintf(stderr,
			        "mmap scope ddr a failed (non-fatal), %d\n",
			        errno);
			param->mapped_buf_a = NULL;
		}
	}
	if (param->channel == 1 || param->channel == 2) {
		/* TODO get phys addr and size from sysfs */
		param->buf_b_size = 0x00200000;
		buf_b_addr = RPAD_SCOPE_CHB_BUF;
		param->mapped_buf_b = mmap(NULL, param->buf_b_size, PROT_READ,
		                           MAP_SHARED, param->scope_fd,
		                           buf_b_addr);
		if (param->mapped_buf_b == MAP_FAILED) {
			fprintf(stderr,
			        "mmap scope ddr b failed (non-fatal), %d\n",
			        errno);
			param->mapped_buf_b = NULL;
		}
	}

	for (param->decimation = 1; decimation; decimation >>= 1)
		param->decimation <<= 1;
	param->decimation >>= 1;

	if (!param->mapped_io) {
		goto out;
	}

	/* set up scope decimation */
	*(unsigned long *)(param->mapped_io + 0x14) = param->decimation;
	if (param->decimation)
		*(unsigned long *)(param->mapped_io + 0x28) = 1;

	/* set up filters
	 * SCOPE_a_filt_aa		0x00000030UL
	 * SCOPE_a_filt_bb		0x00000034UL
	 * SCOPE_a_filt_kk		0x00000038UL
	 * SCOPE_a_filt_pp		0x0000003cUL
	 * SCOPE_b_filt_aa		0x00000040UL
	 * SCOPE_b_filt_bb		0x00000044UL
	 * SCOPE_b_filt_kk		0x00000048UL
	 * SCOPE_b_filt_pp		0x0000004cUL
	 */
	/* Equalization filter */
	if (options->scope_equalizer) {
		if (options->scope_hv) {
			/* Low gain = HV */
			*(unsigned long *)(param->mapped_io + 0x30) = 0x4C5F;
			*(unsigned long *)(param->mapped_io + 0x34) = 0x2F38B;
			*(unsigned long *)(param->mapped_io + 0x40) = 0x4C5F;
			*(unsigned long *)(param->mapped_io + 0x44) = 0x2F38B;
		} else {
			/* High gain = LV */
			*(unsigned long *)(param->mapped_io + 0x30) = 0x7D93;
			*(unsigned long *)(param->mapped_io + 0x34) = 0x437C7;
			*(unsigned long *)(param->mapped_io + 0x40) = 0x7D93;
			*(unsigned long *)(param->mapped_io + 0x44) = 0x437C7;
		}
	} else {
		*(unsigned long *)(param->mapped_io + 0x30) = 0;
		*(unsigned long *)(param->mapped_io + 0x34) = 0;
		*(unsigned long *)(param->mapped_io + 0x40) = 0;
		*(unsigned long *)(param->mapped_io + 0x44) = 0;
	}

	/* Shaping filter */
	if (options->scope_shaping) {
		*(unsigned long *)(param->mapped_io + 0x38) = 0xd9999a;
		*(unsigned long *)(param->mapped_io + 0x3c) = 0x2666;
		*(unsigned long *)(param->mapped_io + 0x48) = 0xd9999a;
		*(unsigned long *)(param->mapped_io + 0x4c) = 0x2666;
	} else {
		*(unsigned long *)(param->mapped_io + 0x38) = 0xffffff;
		*(unsigned long *)(param->mapped_io + 0x3c) = 0;
		*(unsigned long *)(param->mapped_io + 0x48) = 0xffffff;
		*(unsigned long *)(param->mapped_io + 0x4c) = 0;
	}

out:
	return 0;
}

void scope_cleanup(struct scope_parameter *param)
{
	if (param->mapped_io)
		munmap(param->mapped_io, 0x00100000UL);

	if (param->mapped_buf_a)
		munmap(param->mapped_buf_a, param->buf_a_size);

	if (param->mapped_buf_b)
		munmap(param->mapped_buf_b, param->buf_b_size);

	close(param->scope_fd);
}
