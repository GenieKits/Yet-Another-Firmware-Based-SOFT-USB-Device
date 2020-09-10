/* ----------------------------------------------------------------------------
 * Copyright (C) 2019-2020 Zach Lee.
 *
 * Licensed under the MIT License, you may not use this file except in
 * compliance with the License.
 *
 * MIT License:
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 *
 * ----------------------------------------------------------------------------
 *
 * $Date:        11. May 2020
 * $Revision:    V0.0.0
 *
 * Project:      Yet Another Firmware Based USB on Microchip dsPIC33
 * Title:        main.h Global header file for all C modules
 *
 *---------------------------------------------------------------------------*/
#ifndef _MAIN_H_
#define _MAIN_H_

#include <p33FJ12MC201.h>

typedef unsigned char   BYTE;
typedef unsigned short  WORD;
typedef unsigned long   DWORD;

#ifndef NULL
#define NULL            ((void*)0)
#endif

#include "usb.h"
#include "hid.h"

extern void _dbg_led_on(void);
extern void _dbg_die(void);
extern void _dbg_send_bytes(WORD c);

#endif
