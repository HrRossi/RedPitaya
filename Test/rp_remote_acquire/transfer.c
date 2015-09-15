/*
 * transfer.c
 *
 *  Created on: 9 Jun 2014
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
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <sys/time.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/uio.h>
#include <sys/ioctl.h>
#include <rp_scope.h>

#include "options.h"
#include "scope.h"

#include <stdlib.h>
#include <string.h>

/******************************************************************************
 * Defines
 ******************************************************************************/
#define min(x, y) (((x) < (y)) ? (x) : (y))

/******************************************************************************
 * Typedefs
 ******************************************************************************/

/******************************************************************************
 * static function prototypes
 ******************************************************************************/
static void int_handler(int sig);
static u_int64_t transfer_readwrite(int sock_fd, struct scope_parameter *param,
                                    option_fields_t *options);
static u_int64_t transfer_buf_mmap(int sock_fd, struct scope_parameter *param,
                                   option_fields_t *options);
static u_int64_t transfer_buf_mmapfile(struct scope_parameter *param,
                                       option_fields_t *options);
static int send_buffer(int sock_fd, option_fields_t *options, const char *buf, size_t len);

/******************************************************************************
 * static variables
 ******************************************************************************/
static volatile int interrupted = 0;
static int sa_set = 0;
static struct sigaction oldsa;
static struct sigaction sa = {
	.sa_handler = int_handler,
};

static int sock_fd = -1;
static int server_sock_fd = -1;
static struct sockaddr_in srv_addr, cli_addr;

/******************************************************************************
 * non-static function definitions
 ******************************************************************************/
void signal_init(void) {
	if (!sigaction(SIGINT, &sa, &oldsa))
		sa_set = 1;
	else
		fprintf(stderr, "configuring signals failed (non-fatal), %s\n", strerror(errno));
}

void signal_exit(void) {
	if (sa_set) {
		sigaction(SIGINT, &oldsa, NULL);
		sa_set = 0;
	}
}

/*
 * initializes socket according to options
 * returns 0 on success, <0 on error
 */
int connection_init(option_fields_t *options)
{
	sock_fd = socket(PF_INET, options->tcp ? SOCK_STREAM : SOCK_DGRAM, 0);
	if (sock_fd < 0) {
		fprintf(stderr, "create socket failed, %s\n", strerror(errno));
		goto error;
	}

	memset(&srv_addr, 0, sizeof(srv_addr));
	srv_addr.sin_family = AF_INET;
	srv_addr.sin_addr.s_addr = inet_addr(options->address);
	srv_addr.sin_port = htons(options->port);

	if (options->mode == server) {
		int optval = 1;

		srv_addr.sin_addr.s_addr = INADDR_ANY;

		if (setsockopt(sock_fd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval))) {
			fprintf(stderr, "setsockopt failed, %s\n", strerror(errno));
		}

		if (bind(sock_fd, (struct sockaddr *)&srv_addr, sizeof(srv_addr))) {
			fprintf(stderr, "bind failed, %s\n", strerror(errno));
			goto error_close;
		}
		if (listen(sock_fd, 5)) {
			fprintf(stderr, "listen failed, %s\n", strerror(errno));
			goto error_close;
		}

		server_sock_fd = sock_fd;
		sock_fd = -1;
	}

	return 0;

error_close:
	if (sock_fd >= 0) {
		close(sock_fd);
		sock_fd = -1;
	}
error:
	return -1;
}

int connection_start(option_fields_t *options)
{
	if (options->mode == client) {
		if (sock_fd < 0) {
			sock_fd = socket(PF_INET, options->tcp ? SOCK_STREAM : SOCK_DGRAM, 0);
			if (sock_fd < 0) {
				fprintf(stderr, "create socket failed, %s\n", strerror(errno));
				goto error;
			}

			usleep(100000); /* sleep 0.1s before reconnecting */
		}

		if (connect(sock_fd, (struct sockaddr *)&srv_addr, sizeof(srv_addr)) < 0) {
			fprintf(stderr, "connect failed, %s\n", strerror(errno));
			goto error_close;
		}
	} else {
		socklen_t cli_len = sizeof(cli_addr);

		sock_fd = accept(server_sock_fd, (struct sockaddr *)&cli_addr, &cli_len);
		if (sock_fd < 0) {
			fprintf(stderr, "accept failed, %s\n", strerror(errno));
			goto error;
		}
	}

	return sock_fd;

error_close:
	if (sock_fd >= 0) {
		close(sock_fd);
		sock_fd = -1;
	}
error:
	return -1;
}

void connection_stop(void)
{
	close(sock_fd);
	sock_fd = -1;
}

void connection_cleanup(void)
{
	if (sock_fd >= 0) {
		close(sock_fd);
		sock_fd = -1;
	}
	if (server_sock_fd >= 0) {
		close(server_sock_fd);
		server_sock_fd = -1;
	}
}

int transfer_data(int sock_fd, struct scope_parameter *param,
                  option_fields_t *options)
{
	int retval = 0;
	unsigned long duration = 0UL;
	u_int64_t transferred = 0ULL;
	struct timeval start_time, end_time;
	int report_rate = options->report_rate;

	if (report_rate && gettimeofday(&start_time, NULL))
		report_rate = 0;

	if (options->mode == client || options->mode == server) {
		if (0) /* TODO depending on mmap success */
			transferred = transfer_readwrite(sock_fd, param, options);
		else
			transferred = transfer_buf_mmap(sock_fd, param, options);
	} else if (options->mode == file) {
		if (0) /* TODO depending on mmap success */
			/*transferred = transfer_readwritefile(sock_fd, param, options)*/;
		else
			transferred = transfer_buf_mmapfile(param, options);
	}

	if (report_rate && !gettimeofday(&end_time, NULL)) {
		duration = 1000UL * (end_time.tv_sec - start_time.tv_sec)
		         + (unsigned long)end_time.tv_usec   / 1000UL
		         - (unsigned long)start_time.tv_usec / 1000UL;
		printf("transferred %lluB in %lums (rate %.2fMB/s)\n",
		       transferred, duration,
		       (double)(1000ULL * transferred) / (1024ULL * 1024ULL * duration));
	}

	return retval;
}

int transfer_interrupted(void)
{
	return interrupted;
}

/******************************************************************************
 * static function definitions
 ******************************************************************************/
static void int_handler(int sig)
{
	interrupted = 1;
}

/*
 * transfers samples to socket via read() call on rpad_scope
 */
static u_int64_t transfer_readwrite(int sock_fd, struct scope_parameter *param,
                                    option_fields_t *options)
{
	u_int64_t transferred = 0ULL;
	u_int64_t size = 1024ULL * options->kbytes_to_transfer;
	int block_length;
	char buffer[16384];

	while (!size || transferred < size) {
		if (!size)
			block_length = sizeof(buffer);
		else
			block_length = min(sizeof(buffer), size - transferred);

		block_length = read(param->scope_fd, buffer, block_length);
		if (block_length < 0 || interrupted) {
			if (!interrupted)
				fprintf(stderr, "rpad read failed, %s\n", strerror(errno));
			break;
		}

		if (send_buffer(sock_fd, options, buffer, block_length) < 0) {
			if (!interrupted)
				fprintf(stderr, "socket write failed, %s\n", strerror(errno));
			break;
		}

		transferred += block_length;
	}

	return transferred;
}

/*
 * transfers samples to socket from non-cacheable mmap'ed scope buffer via a
 * cacheable intermediate buffer
 */
static u_int64_t transfer_buf_mmap(int sock_fd, struct scope_parameter *param,
                                   option_fields_t *options)
{
	const int CHUNK = 8 * 4096;
	u_int64_t transferred = 0ULL;
	u_int64_t size = 1024ULL * options->kbytes_to_transfer;
	unsigned long pos;
	size_t len;
	unsigned long curr;
	unsigned long *curr_addr;
	unsigned long base;
	void *mapped_base;
	size_t buf_size;
	void *buf;

	if (!(buf = malloc(CHUNK))) {
		fprintf(stderr, "no memory for temp buffer\n");
		return 0ULL;
	}

	curr_addr = param->mapped_io + (options->scope_chn ? 0x118 : 0x114);
	base = *(unsigned long *)(param->mapped_io +
	                          (options->scope_chn ? 0x10c : 0x104));
	mapped_base = options->scope_chn ? param->mapped_buf_b
	                                 : param->mapped_buf_a;
	buf_size = options->scope_chn ? param->buf_b_size : param->buf_a_size;

	pos = 0;
	while (!size || transferred < size) {
		if (pos == buf_size)
			pos = 0;

		curr = *curr_addr - base;

		if (pos + CHUNK <= curr) {
			len = CHUNK;
		} else if (pos > curr) {
			if (pos + CHUNK <= buf_size) {
				len = CHUNK;
			} else {
				len = buf_size - pos;
			}
		} else {
			continue;
		}

		/* copy to cacheable buffer, shortens socket overhead by ~75% */
		memcpy(buf, mapped_base + pos, len);

		if (send_buffer(sock_fd, options, buf, len) < 0) {
			if (!interrupted)
				fprintf(stderr, "socket write failed, %s\n", strerror(errno));
			break;
		}

		pos += len;
		transferred += len;
	}

	free(buf);

	return transferred;
}

/*
 * transfers samples to file from non-cacheable mmap'ed scope buffer via a
 * cacheable intermediate buffer
 */
static u_int64_t transfer_buf_mmapfile(struct scope_parameter *param,
                                       option_fields_t *options)
{
	const int CHUNK = 8 * 4096;
	u_int64_t transferred = 0ULL;
	u_int64_t size = 1024ULL * options->kbytes_to_transfer;
	unsigned long pos;
	size_t len;
	unsigned long curr;
	unsigned long *curr_addr;
	unsigned long base;
	void *mapped_base;
	size_t buf_size;
	FILE *f;
	void *buf;

	if (!(buf = malloc(CHUNK))) {
		fprintf(stderr, "no memory for temp buffer\n");
		return 0ULL;
	}

	if (!(f = fopen(options->fname, "wb"))) {
		fprintf(stderr, "file open failed, %s\n", strerror(errno));
		free(buf);
		return 0ULL;
	}

	curr_addr = param->mapped_io + (options->scope_chn ? 0x118 : 0x114);
	base = *(unsigned long *)(param->mapped_io +
	                          (options->scope_chn ? 0x10c : 0x104));
	mapped_base = options->scope_chn ? param->mapped_buf_b
	                                 : param->mapped_buf_a;
	buf_size = options->scope_chn ? param->buf_b_size : param->buf_a_size;

	pos = 0;
	while (!size || transferred < size) {
		if (pos == buf_size)
			pos = 0;

		curr = *curr_addr - base;

		if (pos + CHUNK <= curr) {
			len = CHUNK;
		} else if (pos > curr) {
			if (pos + CHUNK <= buf_size) {
				len = CHUNK;
			} else {
				len = buf_size - pos;
			}
		} else {
			continue;
		}

		/* copy to cacheable buffer, shortens file overhead */
		memcpy(buf, mapped_base + pos, len);

		len = fwrite(buf, 1, len, f);
		if (len <= 0 || interrupted) {
			if (!interrupted)
				fprintf(stderr, "file write failed, %s\n", strerror(errno));
			break;
		}

		pos += len;
		transferred += len;
	}

	fclose(f);
	free(buf);

	return transferred;
}

static int send_buffer(int sock_fd, option_fields_t *options, const char *buf, size_t len)
{
	int retval = 0;
	int sent;
	unsigned int pos;
	size_t clen;

	for (pos = 0; pos < len; pos += sent) {
		if (options->tcp)
			clen = len - pos;
		else
			clen = (len - pos >= 512) ? 512 : len - pos;
		sent = send(sock_fd, buf + pos, clen, MSG_NOSIGNAL);
		if (sent < 0 || interrupted) {
			retval = -1;
			break;
		}
	}

	return retval;
}

