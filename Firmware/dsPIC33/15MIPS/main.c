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
 * Title:        main.c The main task loop.
 *
 *---------------------------------------------------------------------------*/
#include "main.h"

void setup(void)
{
    _TRISB15 = 0; /* drive the LED on RB15 */
    HID_vInit(0);
}

void loop(void)
{
    WORD Req;

    _RB15 = 0;

    if (HID_bRxRequest(&Req, sizeof(Req)) == 1)
    {
        while(Req--)
        {
            /* prevent empty loop optimazation of GCC */
            _RB15 = 1;
        }
        HID_bTxResult(&Req, sizeof(Req));
    }
}
