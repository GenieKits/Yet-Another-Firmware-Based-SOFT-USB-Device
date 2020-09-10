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
 * Title:        usb.h The header file for hid.c
 *
 *---------------------------------------------------------------------------*/
#ifndef _USB_H_
#define _USB_H_

#define USB_REQ_IGNOR     0x00
#define USB_REQ_SETUP			0x01
#define USB_REQ_INTRO			0x02
#define USB_REQ_DEBUG     0xFF

/*-----------------------------------------------------------------------------
** use these two variables directly is NOT recommended. use API functions
** defined in sie.s instead.
**---------------------------------------------------------------------------*/
extern volatile WORD _uendpt0;
extern volatile WORD _ucontr0;
/* API functions in sie.s */
extern BYTE _usbGetSetup(BYTE * setup);
extern void _usbLoadData(BYTE * _data, BYTE length);
extern BYTE _usbReadData(BYTE * _data, BYTE length);
extern void _usbSendZLP(void);
extern void _usbWaitZLP(void);
extern void _usbSetAddress(BYTE a);
extern void _usbSetConfig(BYTE c);

#define ENDPOINT0_SIZE          8

void USB_vInit(void);

BYTE USB_bRxRequest(void* Request);

BYTE USB_bGetCtrlData(BYTE * dat, WORD siz, WORD exLength);

BYTE USB_bSendCtrlData(BYTE* dat, WORD siz, WORD exLength);

#endif
