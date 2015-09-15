/*
 * transfer.h
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

#ifndef TRANSFER_H_
#define TRANSFER_H_

#include <stdlib.h>

#include "options.h"
#include "scope.h"

void signal_init(void);
void signal_exit(void);
int connection_init(option_fields_t *options);
int connection_start(option_fields_t *options);
void connection_stop();
void connection_cleanup();
int transfer_data(int sock_fd, struct scope_parameter *param,
                  option_fields_t *options);

int transfer_interrupted(void);

#endif /* TRANSFER_H_ */
