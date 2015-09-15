/*
 * main.c
 *
 *  Created on: 7 Jun 2014
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
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <getopt.h>
#include <unistd.h>
#include <stdint.h>

#include "scope.h"
#include "transfer.h"
#include "options.h"

/******************************************************************************
 * Defines
 ******************************************************************************/

/******************************************************************************
 * Typedefs
 ******************************************************************************/

/******************************************************************************
 * static function prototypes
 ******************************************************************************/

/******************************************************************************
 * static variables
 ******************************************************************************/
static option_fields_t g_options =
{
	/* Setting defaults */
	.address = "",
	.port = 14000,
	.tcp = 1,
	.mode = client,
	.kbytes_to_transfer = 0,
	.fname = "/tmp/out",
	.report_rate = 0,
	.scope_chn = 0,
	.scope_dec = 32,
	.scope_equalizer = 1,
	.scope_hv = 0,
	.scope_shaping = 1,
};

/******************************************************************************
 * non-static function definitions
 ******************************************************************************/
int main(int argc, char **argv)
{
	int retval;
	int sock_fd = -1;
	struct scope_parameter param;

	if(0 != handle_options(argc,argv, &g_options))
	{
		usage(argv[0]);
		return 1;
	}

	signal_init();

	if (scope_init(&param, &g_options)) {
		retval = 2;
		goto cleanup;
	}

	if (g_options.mode == client || g_options.mode == server) {
		if (connection_init(&g_options)) {
			retval = 3;
			goto cleanup_scope;
		}
	}

	retval = 0;
	while (!transfer_interrupted()) {
		if (g_options.mode == client || g_options.mode == server) {
			if ((sock_fd = connection_start(&g_options)) < 0) {
				fprintf(stderr, "%s: problem opening connection.\n", __func__);
				continue;
			}
		}

		retval = transfer_data(sock_fd, &param, &g_options);
		if (retval && !transfer_interrupted())
			fprintf(stderr, "%s: problem transferring data.\n", __func__);

		if (g_options.mode == client || g_options.mode == server)
			connection_stop();

		if (g_options.mode == file)
			break;
	}

	connection_cleanup();

cleanup_scope:
	scope_cleanup(&param);
cleanup:
	signal_exit();

	return retval;
}
